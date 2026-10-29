#!/usr/bin/env bash
# Sauvegarde logique (pg_dump -Fc) + sauvegarde brute du volume (tar).
# Aucun client psql sur l'hôte : tout passe par des conteneurs.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${COMPOSE_FILE:-starter/compose.yml}"
SERVICE="${SERVICE:-db}"
VOLUME="${VOLUME:-}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP="${KEEP:-7}"
TS=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "$BACKUP_DIR/logical" "$BACKUP_DIR/raw"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

if [ -z "$VOLUME" ]; then
  VOLUME=$(compose config --volumes | head -1)
  # Préfixe projet Compose (name: shopdata → shopdata_pgdata)
  project=$(compose config --format json | jq -r '.name')
  VOLUME="${project}_${VOLUME}"
fi

echo "==> dump logique → backups/logical/shop-${TS}.dump"
compose exec -T "$SERVICE" \
  pg_dump -U shop -d shop -Fc -f /tmp/shop.dump
cid=$(compose ps -q "$SERVICE")
docker cp "${cid}:/tmp/shop.dump" "$BACKUP_DIR/logical/shop-${TS}.dump"
compose exec -T "$SERVICE" rm -f /tmp/shop.dump

echo "==> dump brut du volume ${VOLUME} → backups/raw/pgdata-${TS}.tar.gz"
# Cohérence : le dump logique ci-dessus est cohérent. Le tar brut d'un volume
# Postgres en marche peut être incohérent (écritures concurrentes). Pour un
# snapshot cohérent : arrêter Postgres, ou pg_backup_start / pg_backup_stop
# (mode archive WAL) avant le tar. Ici on arrête brièvement le service.
compose stop "$SERVICE"
docker run --rm \
  -v "${VOLUME}:/data:ro" \
  -v "$(pwd)/$BACKUP_DIR/raw:/out" \
  alpine:3.20 \
  tar -czf "/out/pgdata-${TS}.tar.gz" -C /data .
compose start "$SERVICE"
compose exec -T "$SERVICE" pg_isready -U shop -d shop >/dev/null
# Attendre healthy si healthcheck présent
for _ in $(seq 1 30); do
  if compose exec -T "$SERVICE" pg_isready -U shop -d shop >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> rétention : conserve les ${KEEP} derniers dumps de chaque type"
trim() {
  local dir=$1
  local pattern=$2
  # shellcheck disable=SC2012
  ls -1t "$dir"/$pattern 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r f; do
    echo "    purge $f"
    rm -f "$f"
  done
}
trim "$BACKUP_DIR/logical" 'shop-*.dump'
trim "$BACKUP_DIR/raw" 'pgdata-*.tar.gz'

echo "OK logical=$(ls -1 "$BACKUP_DIR/logical"/shop-${TS}.dump)"
echo "OK raw=$(ls -1 "$BACKUP_DIR/raw"/pgdata-${TS}.tar.gz)"
echo "$TS"
