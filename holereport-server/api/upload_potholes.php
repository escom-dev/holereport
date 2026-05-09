<?php
require_once __DIR__ . '/db.php';
cors();
requireApiKey();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

$body = file_get_contents('php://input');
$data = json_decode($body, true);

if (!is_array($data) || !isset($data['events']) || !is_array($data['events'])) {
    json_out(['error' => 'Invalid payload — expected {"device_id":"…","events":[…]}'], 400);
}

$deviceId = trim($data['device_id'] ?? '');
$events   = $data['events'];
$pdo      = db();

// Upsert device → get user_id
$userId = null;
if ($deviceId !== '') {
    $userId = upsertUser($pdo, $deviceId);
}

// Insert events — skip duplicates via ON CONFLICT
$stmt = $pdo->prepare("
    INSERT INTO potholes
        (user_id, device_id, detected_at, latitude, longitude, speed_kmh, peak_g, accuracy_m)
    VALUES
        (:user_id, :device_id, :detected_at, :lat, :lon, :speed_kmh, :peak_g, :accuracy_m)
    ON CONFLICT (device_id, detected_at, latitude, longitude) DO NOTHING
");

$inserted = 0;
$skipped  = 0;

foreach ($events as $e) {
    if (empty($e['timestamp']) || !isset($e['latitude']) || !isset($e['longitude'])) {
        $skipped++;
        continue;
    }
    $stmt->execute([
        ':user_id'     => $userId,
        ':device_id'   => $deviceId ?: null,
        ':detected_at' => $e['timestamp'],
        ':lat'         => (float)$e['latitude'],
        ':lon'         => (float)$e['longitude'],
        ':speed_kmh'   => isset($e['speed_kmh'])  ? (float)$e['speed_kmh']  : null,
        ':peak_g'      => isset($e['peak_g'])      ? (float)$e['peak_g']     : null,
        ':accuracy_m'  => isset($e['accuracy_m'])  ? (float)$e['accuracy_m'] : null,
    ]);
    if ($stmt->rowCount() > 0) $inserted++;
    else $skipped++;
}

json_out(['inserted' => $inserted, 'skipped' => $skipped, 'total_sent' => count($events)], 201);
