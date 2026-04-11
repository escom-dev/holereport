<?php
require_once __DIR__ . '/db.php';
cors();
json_out(['user' => getCurrentUser()]);
