<?php
require_once __DIR__ . '/db.php';
cors();

$method = $_SERVER['REQUEST_METHOD'];
$pdo    = db();

// ── GET — public list of active categories ────────────────────────────────────
if ($method === 'GET') {
    $rows = $pdo->query(
        "SELECT id, slug, name, name_en, color, sort_order
         FROM categories
         WHERE is_active = true
         ORDER BY sort_order ASC, id ASC"
    )->fetchAll();

    foreach ($rows as &$r) {
        $r['id']         = (int)$r['id'];
        $r['sort_order'] = (int)$r['sort_order'];
    }
    unset($r);

    json_out(['categories' => $rows]);
}

// ── POST — create category (API key required) ─────────────────────────────────
if ($method === 'POST') {
    requireApiKey();
    $body = json_decode(file_get_contents('php://input'), true);
    if (!$body || empty($body['slug']) || empty($body['name'])) {
        json_out(['error' => 'slug and name are required'], 400);
    }
    $stmt = $pdo->prepare("
        INSERT INTO categories (slug, name, name_en, color, sort_order, is_active)
        VALUES (:slug, :name, :name_en, :color, :sort_order, :is_active)
        RETURNING id, slug, name, name_en, color, sort_order, is_active
    ");
    $stmt->execute([
        ':slug'       => $body['slug'],
        ':name'       => $body['name'],
        ':name_en'    => $body['name_en']    ?? '',
        ':color'      => $body['color']      ?? '#3b82f6',
        ':sort_order' => (int)($body['sort_order'] ?? 0),
        ':is_active'  => isset($body['is_active']) ? (bool)$body['is_active'] : true,
    ]);
    $cat = $stmt->fetch();
    $cat['id']         = (int)$cat['id'];
    $cat['sort_order'] = (int)$cat['sort_order'];
    $cat['is_active']  = (bool)$cat['is_active'];
    json_out($cat, 201);
}

// ── PUT — update category (API key required) ──────────────────────────────────
if ($method === 'PUT') {
    requireApiKey();
    $id   = (int)($_GET['id'] ?? 0);
    $body = json_decode(file_get_contents('php://input'), true);
    if (!$id || !$body) json_out(['error' => 'Bad request'], 400);

    $fields = [];
    $params = [':id' => $id];
    foreach (['slug', 'name', 'name_en', 'color'] as $k) {
        if (array_key_exists($k, $body)) {
            $fields[]      = "$k = :$k";
            $params[":$k"] = $body[$k];
        }
    }
    if (array_key_exists('sort_order', $body)) {
        $fields[]             = "sort_order = :sort_order";
        $params[':sort_order'] = (int)$body['sort_order'];
    }
    if (array_key_exists('is_active', $body)) {
        $fields[]             = "is_active = :is_active";
        $params[':is_active'] = (bool)$body['is_active'];
    }
    if (!$fields) json_out(['error' => 'Nothing to update'], 400);

    $stmt = $pdo->prepare(
        "UPDATE categories SET " . implode(', ', $fields) .
        " WHERE id = :id RETURNING id, slug, name, name_en, color, sort_order, is_active"
    );
    $stmt->execute($params);
    $cat = $stmt->fetch();
    if (!$cat) json_out(['error' => 'Not found'], 404);
    $cat['id']         = (int)$cat['id'];
    $cat['sort_order'] = (int)$cat['sort_order'];
    $cat['is_active']  = (bool)$cat['is_active'];
    json_out($cat);
}

// ── DELETE — remove category (API key required) ───────────────────────────────
if ($method === 'DELETE') {
    requireApiKey();
    $id = (int)($_GET['id'] ?? 0);
    if (!$id) json_out(['error' => 'Missing id'], 400);
    // Nullify FK in photos first (or let ON DELETE SET NULL handle it)
    $pdo->prepare("DELETE FROM categories WHERE id = :id")->execute([':id' => $id]);
    json_out(['success' => true]);
}

json_out(['error' => 'Method not allowed'], 405);
