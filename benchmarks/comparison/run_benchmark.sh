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

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

start_and_bench() {
  local name="$1"
  local cmd="$2"
  local port="$3"
  local wait="${4:-3}"

  eval "$cmd" > /dev/null 2>&1 &
  local pid=$!
  sleep $wait

  curl -s http://localhost:$port/health > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "  $name — FAILED TO START"
    echo ""
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return
  fi

  local result=$(wrk -t$THREADS -c$CONNECTIONS -d${DURATION}s http://localhost:$port/health 2>&1)
  local rps=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
  local lat=$(echo "$result" | grep "Latency" | awk '{print $2}')

  printf "  %-40s %12s req/s  %10s avg\n" "$name" "$rps" "$lat"

  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 1
}

cd "$ROOT"

echo "  Framework                                     Req/sec     Latency"
echo "  ────────────────────────────────────────────────────────────────────"

# Ruby
start_and_bench "Whoosh + Puma (4w×4t, preload)" \
  "bundle exec puma '$DIR/whoosh_config.ru' -p 3001 -w 4 -t 4:4 --preload -q" 3001 8

start_and_bench "Whoosh + Falcon" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3002 -s falcon -q" 3002 4

start_and_bench "Whoosh + Puma (single)" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3000 -s puma -q" 3000

start_and_bench "Roda + Puma (4w×4t, preload)" \
  "bundle exec puma '$DIR/roda_config.ru' -p 3004 -w 4 -t 4:4 --preload -q" 3004 8

start_and_bench "Sinatra + Puma (4w×4t, preload)" \
  "bundle exec puma '$DIR/sinatra_config.ru' -p 3003 -w 4 -t 4:4 --preload -q" 3003 8

start_and_bench "Whoosh + WEBrick" \
  "bundle exec rackup '$DIR/whoosh_config.ru' -p 3010 -q" 3010

echo ""

# Node.js
start_and_bench "Fastify (Node.js)" \
  "cd '$DIR' && PORT=3007 node fastify_app.js" 3007 2

echo ""

# Python
start_and_bench "FastAPI + uvicorn" \
  "cd '$DIR' && /opt/homebrew/bin/python3 -m uvicorn fastapi_app:app --host localhost --port 3005 --log-level error" 3005

echo ""

# PHP
if command -v php &> /dev/null; then
  start_and_bench "PHP built-in (raw)" \
    "php -S localhost:3006 '$DIR/laravel_app.php'" 3006 2
fi

echo ""
echo "  ────────────────────────────────────────────────────────────────────"
echo "  Benchmark complete!"
