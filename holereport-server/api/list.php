<?php
require_once __DIR__ . '/db.php';
cors();

$page       = max(1, (int)($_GET['page']  ?? 1));
$limit      = max(1, min(500, (int)($_GET['limit'] ?? 20)));
$dir        = (($_GET['sort'] ?? 'newest') === 'oldest') ? 'ASC' : 'DESC';
$userId     = isset($_GET['user_id'])     ? (int)$_GET['user_id']     : null;
$categoryId = isset($_GET['category_id']) ? (int)$_GET['category_id'] : null;

$pdo  = db();
$base = baseUrl();

// Build WHERE
$conditions = [];
$params     = [];
if ($userId !== null) {
    $conditions[] = 'p.user_id = :uid';
    $params[':uid'] = $userId;
}
if ($categoryId !== null) {
    $conditions[] = 'p.category_id = :cat_id';
    $params[':cat_id'] = $categoryId;
}
$where = $conditions ? ('WHERE ' . implode(' AND ', $conditions)) : '';

// Count
$countStmt = $pdo->prepare("SELECT COUNT(*) FROM photos p $where");
$countStmt->execute($params);
$total  = (int)$countStmt->fetchColumn();
$pages  = max(1, (int)ceil($total / $limit));
$offset = ($page - 1) * $limit;

// Fetch — measurements are a JSONB column in photos; JOIN users and categories
$sql = "
  SELECT p.*, u.device_id, c.name AS category_name, c.name_en AS category_name_en, c.color AS category_color
  FROM photos p
  LEFT JOIN users      u ON u.id = p.user_id
  LEFT JOIN categories c ON c.id = p.category_id
  $where
  ORDER BY p.uploaded_at $dir
  LIMIT :lim OFFSET :off
";

$stmt = $pdo->prepare($sql);
foreach ($params as $k => $v) $stmt->bindValue($k, $v, PDO::PARAM_INT);
$stmt->bindValue(':lim', $limit, PDO::PARAM_INT);
$stmt->bindValue(':off', $offset, PDO::PARAM_INT);
$stmt->execute();

$rows   = $stmt->fetchAll();
$photos = array_map(function($r) use ($base) { return rowToPhoto($r, $base); }, $rows);

json_out(['photos' => $photos, 'total' => $total, 'page' => $page, 'pages' => $pages, 'limit' => $limit]);
