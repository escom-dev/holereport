<?php
require_once __DIR__ . '/db.php';
cors();
requireApiKey();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

$body = json_decode(file_get_contents('php://input'), true) ?? [];

$email    = trim($body['email']     ?? '');
$password = trim($body['password']  ?? '');
$deviceId = trim($body['device_id'] ?? '');
$allowed  = ['user', 'admin', 'cityadmin', 'superadmin'];
$userType = in_array($body['user_type'] ?? '', $allowed, true) ? $body['user_type'] : 'user';

if (!$email)    json_out(['error' => 'Email is required'],    400);
if (!$password) json_out(['error' => 'Password is required'], 400);
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) json_out(['error' => 'Invalid email address'], 400);

$pdo  = db();
$hash = password_hash($password, PASSWORD_BCRYPT);

// ── Try to find existing user by device_id ─────────────────────────────────
if ($deviceId !== '') {
    $stmt = $pdo->prepare("SELECT id FROM users WHERE device_id = :did LIMIT 1");
    $stmt->execute([':did' => $deviceId]);
    $existingId = $stmt->fetchColumn();

    if ($existingId) {
        // Update email and password (and user_type if provided) for the existing device user
        $pdo->prepare("
            UPDATE users
            SET user_mail = :mail, user_password = :hash, user_type = :type, last_seen = NOW()
            WHERE id = :id
        ")->execute([
            ':mail' => $email,
            ':hash' => $hash,
            ':type' => $userType,
            ':id'   => $existingId,
        ]);
        json_out(['ok' => true, 'id' => (int)$existingId, 'email' => $email,
                  'user_type' => $userType, 'action' => 'updated']);
    }
}

// ── No device match — check for duplicate email before inserting ───────────
$dup = $pdo->prepare("SELECT id FROM users WHERE user_mail = :mail LIMIT 1");
$dup->execute([':mail' => $email]);
if ($dup->fetchColumn()) json_out(['error' => 'Email already registered'], 409);

// ── Insert new user ────────────────────────────────────────────────────────
$newDeviceId = $deviceId !== '' ? $deviceId : ('web-' . bin2hex(random_bytes(16)));

$stmt = $pdo->prepare("
    INSERT INTO users (device_id, user_mail, user_password, user_type, first_seen, last_seen, photo_count)
    VALUES (:did, :mail, :hash, :type, NOW(), NOW(), 0)
    RETURNING id
");
$stmt->execute([
    ':did'  => $newDeviceId,
    ':mail' => $email,
    ':hash' => $hash,
    ':type' => $userType,
]);
$newId = (int)$stmt->fetchColumn();

json_out(['ok' => true, 'id' => $newId, 'email' => $email,
          'user_type' => $userType, 'action' => 'created'], 201);
