<?php
require_once __DIR__ . '/db.php';
cors();

$id = preg_replace('/[^a-f0-9\-]/', '', $_GET['id'] ?? '');
if (!$id) json_out(['error' => 'Missing id'], 400);

$pdo  = db();
$stmt = $pdo->prepare("
  SELECT p.*, u.device_id
  FROM photos p
  LEFT JOIN users u ON u.id = p.user_id
  WHERE p.uuid = :uuid
");
$stmt->execute([':uuid' => $id]);
$row = $stmt->fetch();
if (!$row) json_out(['error' => 'Not found'], 404);

json_out(rowToPhoto($row, baseUrl()));
