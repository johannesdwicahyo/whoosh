#!/bin/bash
set +e

echo "========================================================"
echo "  Real-World Benchmark: GET /users/:id from PostgreSQL"
echo "========================================================"
echo "  1000 users, random ID per request, connection pooling"
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
    printf "  %-45s %s\n" "$name" "FAILED"
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return
  fi

  local result=$(wrk -t$THREADS -c$CONNECTIONS -d${DURATION}s -s "$LUA" http://localhost:$port 2>&1)
  local rps=$(echo "$result" | grep "Requests/sec" | awk '{print $2}')
  local lat=$(echo "$result" | grep "Latency" | awk '{print $2}')

  printf "  %-45s %10s req/s  %10s avg\n" "$name" "$rps" "$lat"

  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 1
}

echo "  Framework                                        Req/sec     Latency"
echo "  ─────────────────────────────────────────────────────────────────────"
echo ""
echo "  --- Single Process ---"

start_and_bench "Whoosh + Falcon" \
  "bundle exec rackup '$DIR/whoosh_pg_config.ru' -p 6001 -s falcon -q" 6001

start_and_bench "Whoosh + Puma (5 threads)" \
  "bundle exec rackup '$DIR/whoosh_pg_config.ru' -p 6002 -s puma -q" 6002

start_and_bench "Roda + Puma" \
  "bundle exec rackup '$DIR/roda_pg_config.ru' -p 6003 -s puma -q" 6003

start_and_bench "Sinatra + Puma" \
  "bundle exec rackup '$DIR/sinatra_pg_config.ru' -p 6004 -s puma -q" 6004

start_and_bench "FastAPI + uvicorn" \
  "cd '$DIR' && /opt/homebrew/bin/python3 -m uvicorn fastapi_pg_app:app --host localhost --port 6005 --log-level error" 6005

start_and_bench "Fastify + pg" \
  "cd '$DIR' && PORT=6006 node fastify_pg_app.js" 6006 3

echo ""
echo "  --- Multi-Worker ---"

start_and_bench "Whoosh + Puma (4w×4t)" \
  "bundle exec puma '$DIR/whoosh_pg_config.ru' -p 6010 -w 4 -t 4:4 --preload -q" 6010 8

start_and_bench "Whoosh + Falcon (4 workers)" \
  "cd '$DIR' && bundle exec falcon serve --bind http://localhost:6011 --count 4 --config whoosh_pg_config.ru -q" 6011 6

start_and_bench "Roda + Puma (4w×4t)" \
  "bundle exec puma '$DIR/roda_pg_config.ru' -p 6012 -w 4 -t 4:4 --preload -q" 6012 8

echo ""
echo "  ─────────────────────────────────────────────────────────────────────"
echo "  Benchmark complete!"
