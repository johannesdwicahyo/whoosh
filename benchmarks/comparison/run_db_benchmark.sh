#!/bin/bash
set +e

echo "========================================================"
echo "  Real-World Benchmark: GET /users/:id from SQLite"
echo "========================================================"
echo "  1000 users seeded, random ID per request"
echo "  Machine: $(uname -m) $(sysctl -n hw.ncpu 2>/dev/null) cores"
echo "  wrk: 4 threads, 100 connections, 10 seconds"
echo "========================================================"
echo ""

DURATION=10
THREADS=4
CONNECTIONS=100

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
LUA="$DIR/random_user.lua"

cd "$ROOT"

# Seed DB if not exists
if [ ! -f "$DIR/bench.sqlite3" ]; then
  bundle exec ruby "$DIR/seed_db.rb"
fi

start_and_bench() {
  local name="$1"
  local cmd="$2"
  local port="$3"
  local wait="${4:-5}"

  eval "$cmd" > /dev/null 2>&1 &
  local pid=$!
  sleep $wait

  curl -s http://localhost:$port/users/1 > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    printf "  %-42s %s\n" "$name" "FAILED TO START"
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return
  fi

  local result=$(wrk -t$THREADS -c$CONNECTIONS -d${DURATION}s -s "$LUA" http://localhost:$port 2>&1)
  local rps=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
  local lat=$(echo "$result" | grep "Latency" | awk '{print $2}')

  printf "  %-42s %10s req/s  %10s avg\n" "$name" "$rps" "$lat"

  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 1
}

echo "  Framework                                     Req/sec     Latency"
echo "  ────────────────────────────────────────────────────────────────────"
echo ""
echo "  --- Single Process ---"

# Whoosh + Falcon
start_and_bench "Whoosh + Falcon" \
  "bundle exec rackup '$DIR/whoosh_db_config.ru' -p 5001 -s falcon -q" 5001

# Whoosh + Puma
start_and_bench "Whoosh + Puma" \
  "bundle exec rackup '$DIR/whoosh_db_config.ru' -p 5002 -s puma -q" 5002

# Roda + Puma
start_and_bench "Roda + Puma" \
  "bundle exec rackup '$DIR/roda_db_config.ru' -p 5003 -s puma -q" 5003

# Sinatra + Puma
start_and_bench "Sinatra + Puma" \
  "bundle exec rackup '$DIR/sinatra_db_config.ru' -p 5004 -s puma -q" 5004

# FastAPI + uvicorn
start_and_bench "FastAPI + uvicorn" \
  "cd '$DIR' && /opt/homebrew/bin/python3 -m uvicorn fastapi_db_app:app --host localhost --port 5005 --log-level error" 5005

# Fastify + better-sqlite3
start_and_bench "Fastify + better-sqlite3" \
  "cd '$DIR' && PORT=5006 node fastify_db_app.js" 5006 3

# PHP
if command -v php &> /dev/null; then
  start_and_bench "PHP built-in + SQLite" \
    "php -S localhost:5007 '$DIR/php_db_app.php'" 5007 2
fi

echo ""
echo "  --- Multi-Worker ---"

# Whoosh + Puma clustered
start_and_bench "Whoosh + Puma (4w×4t)" \
  "bundle exec puma '$DIR/whoosh_db_config.ru' -p 5010 -w 4 -t 4:4 --preload -q" 5010 8

echo ""
echo "  ────────────────────────────────────────────────────────────────────"
echo "  Benchmark complete!"
