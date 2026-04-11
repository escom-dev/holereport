<?php
require_once __DIR__ . '/db.php';
cors();
session_destroy();
json_out(['ok' => true]);
