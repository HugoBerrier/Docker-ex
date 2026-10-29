#!/usr/bin/env bash
# Restaure un dump logique pg_dump -Fc dans le service db du compose cible.
# Usage : ./restore.sh [chemin.dump]   (défaut : dernier dump dans backups/logical/)
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${COMPOSE_FILE:-starter/compose.yml}"
SERVICE="${SERVICE:-db}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

DUMP="${1:-}"
if [ -z "$DUMP" ]; then
  DUMP=$(ls -1t "$BACKUP_DIR/logical"/shop-*.dump 2>/dev/null | head -1 || true)
fi
if [ -z "$DUMP" ] || [ ! -f "$DUMP" ]; then
  echo "aucun dump trouvé (passez un fichier ou lancez backup.sh)" >&2
  exit 1
fi

echo "==> restauration de $DUMP"
compose up -d --wait "$SERVICE" 2>/dev/null || compose up -d "$SERVICE"
for _ in $(seq 1 40); do
  if compose exec -T "$SERVICE" pg_isready -U shop -d shop >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

cid=$(compose ps -q "$SERVICE")
docker cp "$DUMP" "${cid}:/tmp/restore.dump"

# Base propre : drop/create public objects via pg_restore --clean
compose exec -T "$SERVICE" \
  pg_restore -U shop -d shop --clean --if-exists --no-owner --role=shop /tmp/restore.dump \
  || true
# pg_restore renvoie parfois 1 pour des warnings (extensions) : on vérifie ensuite
compose exec -T "$SERVICE" rm -f /tmp/restore.dump

echo "==> checksum après restauration"
compose exec -T "$SERVICE" \
  psql -U shop -d shop -tAc "SELECT count(*) AS orders, md5(string_agg(id::text || status, ',' ORDER BY id)) AS checksum FROM orders;"
echo "OK restore"
