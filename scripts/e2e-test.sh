#!/usr/bin/env bash
# scripts/e2e-test.sh - end-to-end test of the whole voting app.
#
# Starts all five services with Docker Compose (production image stages),
# casts a vote, and checks it travels vote -> Redis -> worker -> Postgres,
# and that the result page is up with the right options.
#
# Usage: ./scripts/e2e-test.sh
# Exits 0 if everything works, 1 otherwise. Always cleans up after itself.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose -p vote-e2e -f docker-compose.yml -f docker-compose.e2e.yml)

# use a throwaway password, never a real one
POSTGRES_PASSWORD="e2e-$(date +%s)-$RANDOM"
export POSTGRES_PASSWORD
export OPTION_A="Kampala"
export OPTION_B="Entebbe"

cleanup() {
    echo "== cleaning up =="
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1"
    echo "== service logs =="
    "${COMPOSE[@]}" logs --tail=30
    exit 1
}

echo "== starting the app =="
# --wait blocks until every service with a healthcheck is healthy
"${COMPOSE[@]}" up -d --build --wait --wait-timeout 180 || fail "services did not become healthy"

echo "== vote page =="
curl -fs http://localhost:8080/ | grep -q "Kampala vs Entebbe" \
    || fail "vote page does not show 'Kampala vs Entebbe'"
echo "PASS: vote page shows the options"

echo "== result page =="
curl -fs http://localhost:8081/healthz | grep -q "ok" || fail "result /healthz is not ok"
curl -fs http://localhost:8081/ | grep -q "Kampala" || fail "result page does not show the options"
echo "PASS: result page is up with the options"

echo "== casting a vote =="
curl -fs -X POST -d "vote=a" http://localhost:8080/ >/dev/null || fail "could not POST a vote"

# the worker takes the vote from Redis and writes it to Postgres; give it up to 60s
count=0
for _ in $(seq 1 30); do
    count=$("${COMPOSE[@]}" exec -T db \
        psql -U postgres -tAc "SELECT COUNT(*) FROM votes WHERE vote = 'a'" 2>/dev/null || echo 0)
    count="${count//[[:space:]]/}"
    [[ "$count" == "1" ]] && break
    sleep 2
done
[[ "$count" == "1" ]] || fail "vote did not reach Postgres (count=$count)"
echo "PASS: vote went vote -> redis -> worker -> postgres"

echo
echo "End-to-end test passed"
