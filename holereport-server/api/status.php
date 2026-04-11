<?php
require_once __DIR__ . '/db.php';
cors();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

$id     = preg_replace('/[^a-f0-9\-]/', '', $_POST['id']     ?? '');
$status = preg_replace('/[^a-z_]/',     '', $_POST['status'] ?? '');

$valid = ['new', 'in_progress', 'resolved', 'closed'];
if (!$id || !in_array($status, $valid, true)) json_out(['error' => 'Invalid parameters'], 400);

$pdo  = db();
$stmt = $pdo->prepare("UPDATE photos SET status = :status WHERE uuid = :uuid RETURNING id");
$stmt->execute([':status' => $status, ':uuid' => $id]);
if (!$stmt->fetchColumn()) json_out(['error' => 'Photo not found'], 404);

json_out(['success' => true, 'status' => $status]);
