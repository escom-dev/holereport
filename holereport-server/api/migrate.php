<?php
/**
 * Migration: JSON meta files → PostgreSQL
 * Run from CLI:  php api/migrate.php
 * Or browser:   GET /api/migrate.php?api_key=YOUR_KEY
 *
 * Schema expected:
 *   photos(id, uuid, user_id, filename, original_name, size_bytes, mime_type,
 *          latitude, longitude, altitude, address, photo_date,
 *          measurements JSONB, device_note, uploaded_at, status)
 *   users(id, device_id, first_seen, last_seen, photo_count)
 */
if (PHP_SAPI !== 'cli') {
    require_once __DIR__ . '/db.php';
    cors();
    if (!checkApiKey()) {
        http_response_code(401);
        echo json_encode(['error' => 'Unauthorized']);
        exit;
    }
} else {
    require_once __DIR__ . '/db.php';
}

$metaDir = ROOT_DIR . '/uploads/meta';
if (!is_dir($metaDir)) {
    $msg = "No meta directory found at $metaDir";
    echo PHP_SAPI === 'cli' ? $msg . "\n" : json_encode(['error' => $msg]);
    exit(0);
}

$pdo   = db();
$files = glob($metaDir . '/photo_*.json') ?: [];
$ok = $skip = $fail = 0;

foreach ($files as $f) {
    $data = json_decode(file_get_contents($f), true);
    if (!$data || empty($data['filename'])) { $fail++; continue; }

    // Derive UUID from filename: photo_UUID.jpg → UUID
    $uuid = preg_replace('/^photo_|\.jpg$/i', '', $data['filename']);

    // Skip if already in DB
    $check = $pdo->prepare("SELECT id FROM photos WHERE uuid = :uuid");
    $check->execute([':uuid' => $uuid]);
    if ($check->fetchColumn()) { $skip++; continue; }

    try {
        $pdo->beginTransaction();

        // Upsert user if device_id is present in the JSON
        $userId   = null;
        $deviceId = $data['device_id'] ?? null;
        if ($deviceId) {
            $userId = upsertUser($pdo, $deviceId);
        }

        // Insert photo — measurements as JSONB
        $stmt = $pdo->prepare("
            INSERT INTO photos
              (uuid, filename, original_name, size_bytes, mime_type, uploaded_at,
               photo_date, latitude, longitude, altitude, address,
               user_id, device_note, measurements, status)
            VALUES
              (:uuid, :filename, :original_name, :size_bytes, :mime_type, :uploaded_at,
               :photo_date, :lat, :lng, :alt, :address,
               :user_id, :device_note, :measurements, :status)
            RETURNING id
        ");
        $stmt->execute([
            ':uuid'          => $uuid,
            ':filename'      => $data['filename'],
            ':original_name' => $data['original_name'] ?? null,
            ':size_bytes'    => $data['size_bytes']     ?? null,
            ':mime_type'     => $data['mime_type']      ?? 'image/jpeg',
            ':uploaded_at'   => $data['uploaded_at']    ?? date('c'),
            ':photo_date'    => $data['photo_date']     ?? null,
            ':lat'           => $data['latitude']       ?? null,
            ':lng'           => $data['longitude']      ?? null,
            ':alt'           => $data['altitude']       ?? null,
            ':address'       => $data['address']        ?? null,
            ':user_id'       => $userId,
            ':device_note'   => $data['device_note']    ?? null,
            ':measurements'  => json_encode($data['measurements'] ?? []),
            ':status'        => $data['status']         ?? 'new',
        ]);

        // Update user's photo_count
        if ($userId) {
            $pdo->prepare("UPDATE users SET photo_count = photo_count + 1 WHERE id = :id")
                ->execute([':id' => $userId]);
        }

        $pdo->commit();
        $ok++;
        echo "Migrated: $uuid\n";

    } catch (\Exception $e) {
        $pdo->rollBack();
        $fail++;
        echo "FAILED $uuid: " . $e->getMessage() . "\n";
    }
}

$result = ['migrated' => $ok, 'skipped' => $skip, 'failed' => $fail];
echo PHP_SAPI === 'cli'
    ? "\nDone — migrated: $ok, skipped: $skip, failed: $fail\n"
    : json_encode($result);
