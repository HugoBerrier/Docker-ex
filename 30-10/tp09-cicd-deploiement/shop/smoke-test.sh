#!/usr/bin/env bash
# /ready, /products avec cache HIT, création d'une commande, statut confirmed par le worker.
set -euo pipefail
cd "$(dirname "$0")"
base="${BASE_URL:-http://api.localhost}"

ready=$(curl -fsS "$base/ready")
printf '%s' "$ready" | jq -e '.status == "ready" and .checks.db == "ok" and .checks.redis == "ok"' >/dev/null
echo "ready ok"

cache=$(curl -fsS -D - -o /dev/null "$base/products" | tr -d '\r')
if ! printf '%s\n' "$cache" | grep -qi '^x-cache: HIT'; then
  printf '%s\n' "$cache" | grep -qi '^x-cache: MISS'
  cache=$(curl -fsS -D - -o /dev/null "$base/products" | tr -d '\r')
  printf '%s\n' "$cache" | grep -qi '^x-cache: HIT'
fi
echo "cache HIT ok"

curl -fsS -X POST "$base/orders" \
  -H 'Content-Type: application/json' \
  -d '{"productId":1,"quantity":2}' >/dev/null

status=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  status=$(docker compose exec -T db sh -c 'PGPASSWORD=$(cat /run/secrets/db_password | tr -d "\n") psql -h 127.0.0.1 -U shop -d shop -tAc "SELECT status FROM orders WHERE product_id=1 ORDER BY id DESC LIMIT 1"')
  status=$(printf '%s' "$status" | tr -d '[:space:]')
  if [ "$status" = "confirmed" ]; then
    echo "commande confirmed"
    exit 0
  fi
  sleep 1
done

echo "commande non confirmée (statut: ${status:-vide})" >&2
exit 1
