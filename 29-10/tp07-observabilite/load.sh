#!/usr/bin/env bash
# Génère de la charge sur l'API (via Traefik ou port direct).
set -euo pipefail
N="${1:-1000}"
BASE="${BASE_URL:-http://api.localhost}"
echo "load: ${N} requêtes vers ${BASE}"
ok=0
fail=0
for i in $(seq 1 "$N"); do
  if curl -fsS -o /dev/null --max-time 3 "$BASE/products"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
  if (( i % 3 == 0 )); then
    curl -fsS -o /dev/null --max-time 3 -X POST "$BASE/orders" \
      -H 'Content-Type: application/json' \
      -d '{"productId":1,"quantity":1}' || fail=$((fail + 1))
  fi
done
echo "ok=${ok} fail=${fail}"
