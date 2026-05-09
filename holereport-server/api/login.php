<?php
require_once __DIR__ . '/db.php';
cors();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

$body = json_decode(file_get_contents('php://input'), true) ?? [];
$mail = trim($body['email'] ?? '');
$pass = $body['password'] ?? '';

if (!$mail || !$pass) json_out(['error' => 'Email and password required'], 400);

$pdo  = db();
$stmt = $pdo->prepare(
    "SELECT id, user_type, user_mail, user_password, city FROM users WHERE user_mail = :mail LIMIT 1"
);
$stmt->execute([':mail' => $mail]);
$row = $stmt->fetch();

if (!$row) json_out(['error' => 'Invalid email or password'], 401);

if (!$row['user_password']) {
    // No password set — only allow superadmin to self-register their password on first login
    if ($row['user_type'] !== 'superadmin') {
        json_out(['error' => 'Invalid email or password'], 401);
    }
    $pdo->prepare("UPDATE users SET user_password = :hash WHERE id = :id")
        ->execute([':hash' => password_hash($pass, PASSWORD_BCRYPT), ':id' => $row['id']]);
} elseif (!password_verify($pass, $row['user_password'])) {
    json_out(['error' => 'Invalid email or password'], 401);
}

$_SESSION['auth_user'] = [
    'id'        => (int)$row['id'],
    'user_type' => $row['user_type'],
    'user_mail' => $row['user_mail'],
    'city'      => $row['city'] ?? null,
];

json_out(['user' => $_SESSION['auth_user']]);
