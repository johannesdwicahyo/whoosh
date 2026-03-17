<?php
header('Content-Type: application/json');

$uri = $_SERVER['REQUEST_URI'];

if (preg_match('#^/users/(\d+)$#', $uri, $matches)) {
    $id = (int)$matches[1];
    $db = new SQLite3(__DIR__ . '/bench.sqlite3', SQLITE3_OPEN_READONLY);
    $stmt = $db->prepare('SELECT id, name, email, age, role FROM users WHERE id = :id');
    $stmt->bindValue(':id', $id, SQLITE3_INTEGER);
    $result = $stmt->execute();
    $row = $result->fetchArray(SQLITE3_ASSOC);
    $db->close();

    if ($row) {
        echo json_encode($row);
    } else {
        http_response_code(404);
        echo json_encode(['error' => 'not_found']);
    }
} else {
    http_response_code(404);
    echo json_encode(['error' => 'not_found']);
}
