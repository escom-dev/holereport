<?php
if (session_status() === PHP_SESSION_NONE) session_start();

define('ROOT_DIR',   dirname(__DIR__));
define('UPLOAD_DIR', ROOT_DIR . '/uploads');
define('THUMB_DIR',  UPLOAD_DIR . '/thumbs');

function getCurrentUser(): ?array {
    return $_SESSION['auth_user'] ?? null;
}

function requireSuperAdmin(): void {
    $u = getCurrentUser();
    if (!$u || ($u['user_type'] ?? '') !== 'superadmin') {
        json_out(['error' => 'Forbidden — superadmin only'], 403);
    }
}

function cors(): void {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: X-API-Key, Content-Type');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
}

function json_out($data, int $code = 200): void {
    header('Content-Type: application/json');
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function getApiKey(): string {
    return getenv('MEASURESNAP_API_KEY') ?: 'api-key-here';
}

function checkApiKey(): bool {
    $key = $_SERVER['HTTP_X_API_KEY'] ?? $_POST['api_key'] ?? $_GET['api_key'] ?? '';
    return $key === getApiKey();
}

function requireApiKey(): void {
    if (!checkApiKey()) json_out(['error' => 'Unauthorized'], 401);
}

// Global handler: any uncaught exception returns JSON instead of empty/HTML response
set_exception_handler(function(\Throwable $e) {
    if (!headers_sent()) {
        http_response_code(500);
        header('Content-Type: application/json');
    }
    echo json_encode(['error' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
    exit;
});

function db(): PDO {
    static $pdo = null;
    if ($pdo !== null) return $pdo;
    $host = getenv('DB_HOST') ?: 'localhost';
    $port = getenv('DB_PORT') ?: '5432';
    $name = getenv('DB_NAME') ?: 'holereport';
    $user = getenv('DB_USER') ?: 'holereport';
    $pass = getenv('DB_PASS') ?: 'db-password-here';
    try {
        $pdo = new PDO(
            "pgsql:host={$host};port={$port};dbname={$name}",
            $user, $pass,
            [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]
        );
    } catch (PDOException $e) {
        json_out(['error' => 'Database connection failed: ' . $e->getMessage()], 500);
    }
    return $pdo;
}

function baseUrl(): string {
    $s = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    return $s . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost');
}

/**
 * Upsert a device into the users table, return users.id.
 * Schema: users(id, device_id, first_seen, last_seen, photo_count)
 */
function upsertUser(PDO $pdo, string $deviceId): int {
    $stmt = $pdo->prepare(
        "INSERT INTO users (device_id, first_seen, last_seen, photo_count)
         VALUES (:did, NOW(), NOW(), 0)
         ON CONFLICT (device_id) DO UPDATE SET last_seen = NOW()
         RETURNING id"
    );
    $stmt->execute([':did' => $deviceId]);
    return (int)$stmt->fetchColumn();
}

/**
 * Convert a DB row to an API photo object.
 * - measurements comes from JSONB column in photos
 * - device_id comes from LEFT JOIN users (column aliased as device_id)
 */
function rowToPhoto(array $r, string $baseUrl): array {
    $filename    = $r['filename'] ?? '';
    $thumbExists = $filename && file_exists(THUMB_DIR . '/' . $filename);

    // Decode measurements from JSONB column
    $meas = [];
    if (!empty($r['measurements'])) {
        $decoded = is_string($r['measurements'])
            ? json_decode($r['measurements'], true)
            : $r['measurements'];
        if (is_array($decoded)) $meas = $decoded;
    }

    return [
        'uuid'               => $r['uuid'],
        'photo_url'          => $baseUrl . '/uploads/' . $filename,
        'thumb_url'          => $thumbExists ? $baseUrl . '/uploads/thumbs/' . $filename : null,
        'uploaded_at'        => $r['uploaded_at'],
        'photo_date'         => $r['photo_date'],
        'size_bytes'         => $r['size_bytes'] !== null ? (int)$r['size_bytes'] : null,
        'latitude'           => $r['latitude']  !== null ? (float)$r['latitude']  : null,
        'longitude'          => $r['longitude'] !== null ? (float)$r['longitude'] : null,
        'altitude'           => $r['altitude']  !== null ? (float)$r['altitude']  : null,
        'address'            => $r['address'],
        'device_id'          => $r['device_id'] ?? null,
        'user_id'            => $r['user_id']   !== null ? (int)$r['user_id'] : null,
        'measurement_count'  => count($meas),
        'measurements'       => $meas,
        'status'             => $r['status'] ?? 'new',
        'category_id'        => $r['category_id']       !== null ? (int)$r['category_id'] : null,
        'category_name'      => $r['category_name']     ?? null,
        'category_name_en'   => $r['category_name_en']  ?? null,
        'category_color'     => $r['category_color']    ?? null,
    ];
}
