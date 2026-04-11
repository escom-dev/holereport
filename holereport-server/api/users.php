<?php
require_once __DIR__ . '/db.php';
cors();

$pdo    = db();
$method = $_SERVER['REQUEST_METHOD'];

// ── PUT — update user_type, user_mail, password ────────────────────────────
if ($method === 'PUT') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $id   = isset($body['id']) ? (int)$body['id'] : 0;
    if (!$id) { http_response_code(400); json_out(['error' => 'id required']); }

    $allowed = ['user', 'admin', 'cityadmin', 'superadmin'];
    $type    = in_array($body['user_type'] ?? '', $allowed, true) ? $body['user_type'] : null;
    $mail    = isset($body['user_mail']) ? trim($body['user_mail']) : null;
    $pass    = isset($body['user_password']) && $body['user_password'] !== ''
               ? password_hash($body['user_password'], PASSWORD_BCRYPT) : null;

    $sets   = [];
    $params = [':id' => $id];

    if ($type !== null)  { $sets[] = 'user_type = :type'; $params[':type'] = $type; }
    if ($mail !== null)  { $sets[] = 'user_mail = :mail'; $params[':mail'] = $mail ?: null; }
    if ($pass !== null)  { $sets[] = 'user_password = :pass'; $params[':pass'] = $pass; }

    if (!$sets) { http_response_code(400); json_out(['error' => 'nothing to update']); }

    $pdo->prepare('UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = :id')
        ->execute($params);

    json_out(['ok' => true]);
}

// ── GET — list all users ───────────────────────────────────────────────────
$stmt = $pdo->query("
  SELECT id, device_id, photo_count, first_seen, last_seen,
         user_type, user_mail
  FROM users
  ORDER BY last_seen DESC
");

$users = [];
foreach ($stmt->fetchAll() as $u) {
    $users[] = [
        'id'          => (int)$u['id'],
        'device_id'   => $u['device_id'],
        'photo_count' => (int)$u['photo_count'],
        'first_seen'  => $u['first_seen'],
        'last_seen'   => $u['last_seen'],
        'user_type'   => $u['user_type'] ?? 'user',
        'user_mail'   => $u['user_mail'],
    ];
}

json_out(['users' => $users, 'total' => count($users)]);
