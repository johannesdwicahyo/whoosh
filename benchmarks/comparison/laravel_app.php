<?php
// Minimal PHP built-in server handler — no framework overhead
// For fair comparison, this is raw PHP (like raw Rack)
// Laravel would be slower due to framework overhead

header('Content-Type: application/json');

$uri = $_SERVER['REQUEST_URI'];

if ($uri === '/health') {
    echo json_encode(['status' => 'ok']);
} else {
    http_response_code(404);
    echo json_encode(['error' => 'not_found']);
}
