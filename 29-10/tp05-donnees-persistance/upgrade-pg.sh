#!/usr/bin/env bash
# Montée de version majeure PostgreSQL 14 → 16 sans perte, volume PG14 conservé.
# Retour arrière : remettre image postgres:14.13-alpine + volume pgdata d'origine.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${COMPOSE_FILE:-starter/compose.yml}"
BACKUP_DIR="${BACKUP_DIR:-./backups/upgrade}"
NEW_VOLUME="${NEW_VOLUME:-shopdata_pgdata16}"
NEW_IMAGE="postgres:16.4-alpine"
TS=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "$BACKUP_DIR"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

checksum() {
  compose exec -T db \
    psql -U shop -d shop -tAc \
    "SELECT count(*) || '|' || coalesce(md5(string_agg(id::text || status, ',' ORDER BY id)),'') FROM orders;" \
    | tr -d '[:space:]'
}

echo "==> 1. démarrage PG14"
compose up -d db
for _ in $(seq 1 60); do
  if compose exec -T db pg_isready -U shop -d shop >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

BEFORE=$(checksum)
echo "checksum avant : $BEFORE"
printf '%s\n' "$BEFORE" > "$BACKUP_DIR/checksum-before-${TS}.txt"

echo "==> 2. dumps (pg_dumpall + pg_dump -Fc)"
cid=$(compose ps -q db)
compose exec -T db pg_dumpall -U shop -f /tmp/all.sql
compose exec -T db pg_dump -U shop -d shop -Fc -f /tmp/shop.dump
docker cp "${cid}:/tmp/all.sql" "$BACKUP_DIR/pg_dumpall-${TS}.sql"
docker cp "${cid}:/tmp/shop.dump" "$BACKUP_DIR/shop-${TS}.dump"

PROJECT=$(compose config --format json | jq -r '.name')
OLD_VOL="${PROJECT}_pgdata"

echo "==> 3. arrêt PG14 (volume ${OLD_VOL} conservé)"
compose stop db
compose rm -f db

echo "==> 4. PG16 sur nouveau volume ${NEW_VOLUME}"
docker volume create "$NEW_VOLUME" >/dev/null
docker rm -f shopdata-pg16-upgrade >/dev/null 2>&1 || true
docker run -d --name shopdata-pg16-upgrade \
  -e POSTGRES_USER=shop \
  -e POSTGRES_PASSWORD=shop \
  -e POSTGRES_DB=shop \
  -v "${NEW_VOLUME}:/var/lib/postgresql/data" \
  "$NEW_IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if docker exec shopdata-pg16-upgrade pg_isready -U shop -d shop >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> 5. pg_restore du dump -Fc"
docker cp "$BACKUP_DIR/shop-${TS}.dump" shopdata-pg16-upgrade:/tmp/shop.dump
set +e
docker exec shopdata-pg16-upgrade \
  pg_restore -U shop -d shop --clean --if-exists --no-owner --role=shop /tmp/shop.dump
set -e

AFTER=$(docker exec shopdata-pg16-upgrade \
  psql -U shop -d shop -tAc \
  "SELECT count(*) || '|' || coalesce(md5(string_agg(id::text || status, ',' ORDER BY id)),'') FROM orders;" \
  | tr -d '[:space:]')
echo "checksum après restore : $AFTER"
printf '%s\n' "$AFTER" > "$BACKUP_DIR/checksum-after-${TS}.txt"

docker stop shopdata-pg16-upgrade >/dev/null
docker rm shopdata-pg16-upgrade >/dev/null

UPGRADE_COMPOSE="starter/compose.pg16.yml"
cat > "$UPGRADE_COMPOSE" <<EOF
# Généré par upgrade-pg.sh — PG16 sur volume dédié. Le volume PG14 (${OLD_VOL}) est intact.
name: shopdata
services:
  db:
    image: ${NEW_IMAGE}
    environment:
      POSTGRES_USER: shop
      POSTGRES_PASSWORD: shop
      POSTGRES_DB: shop
    volumes:
      - pgdata16:/var/lib/postgresql/data
    ports: ["5433:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U shop"]
      interval: 5s
      retries: 10
volumes:
  pgdata16:
    external: true
    name: ${NEW_VOLUME}
EOF

COMPOSE_FILE="$UPGRADE_COMPOSE"
compose up -d db
for _ in $(seq 1 60); do
  if compose exec -T db pg_isready -U shop -d shop >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

FINAL=$(checksum)

echo
echo "======== VERDICT ========"
echo "avant : $BEFORE"
echo "après : $FINAL"
if [ "$BEFORE" = "$FINAL" ]; then
  echo "OK montée de version 14 → 16, checksums identiques"
else
  echo "ECHEC checksums différents" >&2
  exit 1
fi

cat <<EOF

Retour arrière :
  1. docker compose -f starter/compose.pg16.yml down
  2. docker compose -f starter/compose.yml up -d   # volume ${OLD_VOL} toujours là
  (ne pas docker volume rm ${OLD_VOL})

Différence pg_dumpall / pg_dump :
  - pg_dumpall : roles, tablespaces + toutes les bases (cluster entier)
  - pg_dump    : une seule base (ici shop), formats custom -Fc / directory

Pourquoi un nouveau volume :
  - PG16 refuse de démarrer sur des fichiers PGDATA écrits par une majeure
    précédente (erreur « database files are incompatible with server »)
  - garder l'ancien volume = retour arrière immédiat sans re-restore

Réduire l'indisponibilité :
  - réplication logique 14→16, bascule quand le lag est nul
  - pg_upgrade --link dans tianon/postgres-upgrade:14-to-16 (hard links, quasi instantané
    si même filesystem ; plus risqué, nécessite arrêt court)
EOF
