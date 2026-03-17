#!/bin/bash
set +e

echo "========================================================"
echo "  Framework Benchmark: GET /health → {\"status\":\"ok\"}"
echo "========================================================"
echo "Machine: $(uname -m) $(sysctl -n hw.ncpu 2>/dev/null || nproc) cores"
echo "Ruby:    $(ruby -v 2>&1 | head -c 50)"
echo "Python:  $(/opt/homebrew/bin/python3 --version 2>&1)"
echo "Node:    $(node --version 2>&1)"
echo "PHP:     $(php --version 2>&1 | head -1)"
echo "wrk:     4 threads, 100 connections, 10 seconds each"
echo "========================================================"
echo ""

DURATION=10
THREADS=4
CONNECTIONS=100
PORT=3000

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

run_wrk() {
  local name="$1"
  local port="$2"
  echo ">>> $name"
  wrk -t$THREADS -c$CONNECTIONS -d${DURATION}s http://localhost:$port/health 2>&1 | grep -E "(Latency|Requests/sec|Transfer)"
  echo ""
}

start_and_bench() {
  local name="$1"
  local cmd="$2"
  local port="$3"
  local wait="${4:-3}"

  echo "--- Starting $name on port $port ---"
  eval "$cmd" > /dev/null &
  local pid=$!
  sleep $wait

  # Verify it's running
  curl -s http://localhost:$port/health > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo ">>> $name — FAILED TO START"
    echo ""
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return
  fi

  run_wrk "$name" "$port"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 1
}

cd "$ROOT"

# ============ RUBY FRAMEWORKS ============

echo "========== RUBY =========="
echo ""

# Whoosh + WEBrick
start_and_bench \
  "Whoosh + WEBrick" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3000 -q 2>/dev/null" \
  3000

# Whoosh + Puma
start_and_bench \
  "Whoosh + Puma" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3001 -s puma -q 2>/dev/null" \
  3001

# Whoosh + Falcon
start_and_bench \
  "Whoosh + Falcon" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3002 -s falcon -q 2>/dev/null" \
  3002 4

# Sinatra + Puma
start_and_bench \
  "Sinatra + Puma" \
  "bundle exec rackup '$DIR/sinatra_config.ru' -p 3003 -s puma -q 2>/dev/null" \
  3003

# Roda + Puma
start_and_bench \
  "Roda + Puma" \
  "bundle exec rackup '$DIR/roda_config.ru' -p 3004 -s puma -q 2>/dev/null" \
  3004

# ============ PYTHON ============

echo "========== PYTHON =========="
echo ""

# FastAPI + uvicorn
start_and_bench \
  "FastAPI + uvicorn" \
  "cd '$DIR' && /opt/homebrew/bin/python3 -m uvicorn fastapi_app:app --host localhost --port 3005 --log-level error 2>/dev/null" \
  3005

# ============ NODE.JS ============

echo "========== NODE.JS =========="
echo ""

# Fastify
start_and_bench \
  "Fastify" \
  "cd '$DIR' && PORT=3007 node fastify_app.js 2>/dev/null" \
  3007 2

# ============ PHP ============

echo "========== PHP =========="
echo ""

# PHP built-in server
if command -v php &> /dev/null; then
  start_and_bench \
    "PHP built-in server (raw)" \
    "php -S localhost:3006 '$DIR/laravel_app.php' 2>/dev/null" \
    3006 2
else
  echo ">>> PHP — NOT INSTALLED, SKIPPED"
  echo ""
fi

echo "========================================================"
echo "  Benchmark complete!"
echo "========================================================"
