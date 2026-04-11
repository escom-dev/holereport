<?php
require_once __DIR__ . '/db.php';
cors();
requireApiKey();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_out(['error' => 'Method not allowed'], 405);

if (empty($_FILES['photo']) || $_FILES['photo']['error'] !== UPLOAD_ERR_OK) {
    json_out(['error' => 'No photo uploaded or upload error'], 400);
}

$file = $_FILES['photo'];
$ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
if (!in_array($ext, ['jpg', 'jpeg', 'png'], true)) {
    json_out(['error' => 'Invalid file type. Only JPG/PNG allowed.'], 400);
}

// Create directories if needed
foreach ([UPLOAD_DIR, THUMB_DIR] as $dir) {
    if (!is_dir($dir)) mkdir($dir, 0775, true);
}

// Generate UUID v4
$uuid     = sprintf('%08x-%04x-%04x-%04x-%012x',
    random_int(0, 0xffffffff), random_int(0, 0xffff),
    random_int(0, 0x0fff) | 0x4000,
    random_int(0, 0x3fff) | 0x8000,
    random_int(0, 0xffffffffffff));
$filename = "photo_{$uuid}.jpg";
$dest     = UPLOAD_DIR . '/' . $filename;

if (!move_uploaded_file($file['tmp_name'], $dest)) {
    json_out(['error' => 'Failed to save file'], 500);
}

// Generate thumbnail with GD
if (extension_loaded('gd')) {
    $src = @imagecreatefromstring(file_get_contents($dest));
    if ($src) {
        $w = imagesx($src); $h = imagesy($src);
        $tw = 400; $th = (int)round($h * $tw / $w);
        $thumb = imagecreatetruecolor($tw, $th);
        imagecopyresampled($thumb, $src, 0, 0, 0, 0, $tw, $th, $w, $h);
        imagejpeg($thumb, THUMB_DIR . '/' . $filename, 70);
        imagedestroy($src); imagedestroy($thumb);
    }
}

// Parse measurements
$measurements = [];
if (!empty($_POST['measurements'])) {
    $raw = json_decode($_POST['measurements'], true);
    if (is_array($raw)) $measurements = $raw;
}

$deviceId = trim($_POST['device_id'] ?? '');
$pdo = db();

// Upsert user → get user_id, then increment photo_count
$userId = null;
if ($deviceId !== '') {
    $userId = upsertUser($pdo, $deviceId);
    $pdo->prepare("UPDATE users SET photo_count = photo_count + 1, last_seen = NOW() WHERE id = :id")
        ->execute([':id' => $userId]);
}

// Resolve category_id (optional)
$categoryId = null;
if (!empty($_POST['category_id'])) {
    $cid = (int)$_POST['category_id'];
    $chk = $pdo->prepare("SELECT id FROM categories WHERE id = :id AND is_active = true");
    $chk->execute([':id' => $cid]);
    if ($chk->fetchColumn()) $categoryId = $cid;
}

// Insert photo — measurements stored as JSONB
$photoStmt = $pdo->prepare("
  INSERT INTO photos
    (uuid, filename, original_name, size_bytes, mime_type, uploaded_at,
     photo_date, latitude, longitude, altitude, address,
     user_id, device_note, measurements, status, category_id)
  VALUES
    (:uuid, :filename, :original_name, :size_bytes, 'image/jpeg', NOW(),
     :photo_date, :lat, :lng, :alt, :address,
     :user_id, 'iPhone MeasureSnap App', :measurements, 'new', :category_id)
  RETURNING id
");
$photoStmt->execute([
    ':uuid'          => $uuid,
    ':filename'      => $filename,
    ':original_name' => $file['name'],
    ':size_bytes'    => filesize($dest),
    ':photo_date'    => $_POST['photo_date'] ?: null,
    ':lat'           => isset($_POST['latitude'])  ? (float)$_POST['latitude']  : null,
    ':lng'           => isset($_POST['longitude']) ? (float)$_POST['longitude'] : null,
    ':alt'           => isset($_POST['altitude'])  ? (float)$_POST['altitude']  : null,
    ':address'       => $_POST['address'] ?: null,
    ':user_id'       => $userId,
    ':measurements'  => json_encode($measurements),
    ':category_id'   => $categoryId,
]);

json_out(['success' => true, 'photo_url' => baseUrl() . '/uploads/' . $filename], 201);
