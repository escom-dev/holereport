<?php
require_once __DIR__ . '/db.php';
cors();
requireSuperAdmin();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

$id = preg_replace('/[^a-f0-9\-]/', '', $_POST['id'] ?? '');
if (!$id) json_out(['error' => 'Missing id'], 400);

$pdo  = db();
$stmt = $pdo->prepare("SELECT id, filename, user_id FROM photos WHERE uuid = :uuid");
$stmt->execute([':uuid' => $id]);
$row = $stmt->fetch();
if (!$row) json_out(['error' => 'Not found'], 404);

// Delete files from disk
$photoFile = UPLOAD_DIR . '/' . $row['filename'];
$thumbFile  = THUMB_DIR  . '/' . $row['filename'];
if (file_exists($photoFile)) @unlink($photoFile);
if (file_exists($thumbFile))  @unlink($thumbFile);

// Delete from DB
$pdo->prepare("DELETE FROM photos WHERE id = :id")->execute([':id' => $row['id']]);

// Decrement user's photo_count
if ($row['user_id']) {
    $pdo->prepare("UPDATE users SET photo_count = GREATEST(photo_count - 1, 0) WHERE id = :id")
        ->execute([':id' => $row['user_id']]);
}

json_out(['success' => true]);
