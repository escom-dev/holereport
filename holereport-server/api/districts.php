<?php
require_once __DIR__ . '/db.php';
cors();

/** PHP ray-casting point-in-polygon. coordinates = [[lat,lng], ...] */
function pointInPoly(float $lat, float $lng, array $poly): bool {
    $inside = false;
    $n = count($poly);
    for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
        $yi = (float)$poly[$i][0]; $xi = (float)$poly[$i][1];
        $yj = (float)$poly[$j][0]; $xj = (float)$poly[$j][1];
        if ((($yi > $lat) !== ($yj > $lat)) &&
            ($lng < ($xj - $xi) * ($lat - $yi) / ($yj - $yi) + $xi)) {
            $inside = !$inside;
        }
    }
    return $inside;
}

$method = $_SERVER['REQUEST_METHOD'];
$pdo    = db();

if ($method === 'GET') {
    $districts = $pdo->query("SELECT * FROM districts ORDER BY sort_order ASC, id ASC")->fetchAll();

    // Fetch all geolocated photos for photo_count computation
    $photos = $pdo->query("SELECT latitude, longitude FROM photos WHERE latitude IS NOT NULL AND longitude IS NOT NULL")->fetchAll();

    foreach ($districts as &$d) {
        $coords = is_string($d['coordinates']) ? json_decode($d['coordinates'], true) : $d['coordinates'];
        $d['coordinates'] = $coords ?? [];
        $count = 0;
        foreach ($photos as $p) {
            if (pointInPoly((float)$p['latitude'], (float)$p['longitude'], $d['coordinates'])) {
                $count++;
            }
        }
        $d['photo_count'] = $count;
        $d['sort_order']  = (int)$d['sort_order'];
        $d['id']          = (int)$d['id'];
        $d['parent_id']   = $d['parent_id'] !== null ? (int)$d['parent_id'] : null;
    }
    unset($d);

    // Calculate geographic center
    $center = [41.9346, 25.5556];
    if ($districts) {
        $lats = $lngs = [];
        foreach ($districts as $d) {
            foreach ($d['coordinates'] as $c) {
                $lats[] = (float)$c[0];
                $lngs[] = (float)$c[1];
            }
        }
        if ($lats) $center = [array_sum($lats) / count($lats), array_sum($lngs) / count($lngs)];
    }

    json_out(['districts' => $districts, 'center' => $center, 'zoom' => 13]);
}

if ($method === 'POST') {
    requireApiKey();
    $body = json_decode(file_get_contents('php://input'), true);
    if (!$body || empty($body['slug']) || empty($body['name'])) {
        json_out(['error' => 'slug and name are required'], 400);
    }
    $parentId = !empty($body['parent_id']) ? (int)$body['parent_id'] : null;
    $stmt = $pdo->prepare("
        INSERT INTO districts (slug, name, name_en, color, city, sort_order, coordinates, parent_id)
        VALUES (:slug, :name, :name_en, :color, :city, :sort_order, :coords, :parent_id)
        RETURNING *
    ");
    $stmt->execute([
        ':slug'       => $body['slug'],
        ':name'       => $body['name'],
        ':name_en'    => $body['name_en']    ?? '',
        ':color'      => $body['color']      ?? '#3b82f6',
        ':city'       => $body['city']       ?? '',
        ':sort_order' => (int)($body['sort_order'] ?? 0),
        ':coords'     => json_encode($body['coordinates'] ?? []),
        ':parent_id'  => $parentId,
    ]);
    $d = $stmt->fetch();
    $d['coordinates'] = json_decode($d['coordinates'], true);
    $d['id']        = (int)$d['id'];
    $d['parent_id'] = $d['parent_id'] !== null ? (int)$d['parent_id'] : null;
    json_out($d, 201);
}

if ($method === 'PUT') {
    requireApiKey();
    $id   = (int)($_GET['id'] ?? 0);
    $body = json_decode(file_get_contents('php://input'), true);
    if (!$id || !$body) json_out(['error' => 'Bad request'], 400);

    $fields = [];
    $params = [':id' => $id];
    $map = ['slug','name','name_en','color','city','sort_order'];
    foreach ($map as $k) {
        if (array_key_exists($k, $body)) {
            $fields[]   = "$k = :$k";
            $params[":$k"] = $k === 'sort_order' ? (int)$body[$k] : $body[$k];
        }
    }
    if (array_key_exists('parent_id', $body)) {
        $fields[]            = "parent_id = :parent_id";
        $params[':parent_id'] = !empty($body['parent_id']) ? (int)$body['parent_id'] : null;
    }
    if (array_key_exists('coordinates', $body)) {
        $fields[]           = "coordinates = :coords";
        $params[':coords']  = json_encode($body['coordinates']);
    }
    if (!$fields) json_out(['error' => 'Nothing to update'], 400);

    $stmt = $pdo->prepare("UPDATE districts SET " . implode(', ', $fields) . " WHERE id = :id RETURNING *");
    $stmt->execute($params);
    $d = $stmt->fetch();
    if (!$d) json_out(['error' => 'Not found'], 404);
    $d['coordinates'] = json_decode($d['coordinates'], true);
    $d['id']        = (int)$d['id'];
    $d['parent_id'] = $d['parent_id'] !== null ? (int)$d['parent_id'] : null;
    json_out($d);
}

if ($method === 'DELETE') {
    requireApiKey();
    $id = (int)($_GET['id'] ?? 0);
    if (!$id) json_out(['error' => 'Missing id'], 400);
    $pdo->prepare("DELETE FROM districts WHERE id = :id")->execute([':id' => $id]);
    json_out(['success' => true]);
}

json_out(['error' => 'Method not allowed'], 405);
