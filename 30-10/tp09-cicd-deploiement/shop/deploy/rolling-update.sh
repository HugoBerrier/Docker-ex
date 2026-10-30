#!/usr/bin/env bash
# Déploiement sans interruption (start-first) :
# 1) on ajoute de nouveaux réplicas healthy
# 2) on drain l'ancien (disconnect réseau front → Traefik le retire)
# 3) stop -t 15 + rm, un à la fois
# Usage:
#   VERSION=sha-abc123 ./deploy/rolling-update.sh
# Local :
#   SKIP_PULL=1 COMPOSE_FILES="-f compose.yml -f ..." VERSION=local ./deploy/rolling-update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${VERSION:?VERSION requis (ex. sha-<sha> ou 1.4.2)}"
REGISTRY="${REGISTRY:-127.0.0.1:5500}"
REPLICAS="${REPLICAS:-2}"
SKIP_PULL="${SKIP_PULL:-0}"
FRONT_NET="${FRONT_NET:-shop-front}"
DRAIN_SLEEP="${DRAIN_SLEEP:-5}"

# shellcheck disable=SC2206
if [[ -n "${COMPOSE_FILES:-}" ]]; then
  COMPOSE_ARR=( ${COMPOSE_FILES} )
else
  COMPOSE_ARR=(-f compose.yml -f compose.prod.yml)
fi

export REGISTRY VERSION

echo "== rolling update api → ${REGISTRY}/shopapi:${VERSION} (replicas=${REPLICAS}) =="
if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
  echo "DOCKER_CONTEXT=${DOCKER_CONTEXT}"
fi
echo "compose: ${COMPOSE_ARR[*]}"

compose() {
  docker compose "${COMPOSE_ARR[@]}" "$@"
}

api_ids() {
  compose ps -q api 2>/dev/null | tr -d '\r'
}

count_healthy() {
  local healthy=0 id health
  for id in $(api_ids); do
    [[ -z "$id" ]] && continue
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || echo missing)
    if [[ "$health" == "healthy" ]]; then
      healthy=$((healthy + 1))
    fi
  done
  echo "$healthy"
}

wait_healthy() {
  local want="$1" deadline=$((SECONDS + 180)) h
  while (( SECONDS < deadline )); do
    h=$(count_healthy)
    echo "  healthy=${h}/${want}"
    if (( h >= want )); then
      return 0
    fi
    sleep 2
  done
  echo "timeout: pas assez de réplicas healthy" >&2
  compose ps api >&2 || true
  return 1
}

drain() {
  local id="$1" name
  name=$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')
  # 1) /lb-ready → 503 : Traefik retire le backend (mesure /health reste 200)
  # 2) disconnect front : plus aucune nouvelle connexion possible
  echo "  drain ${name} (touch /tmp/drain, wait ${DRAIN_SLEEP}s, disconnect ${FRONT_NET})"
  docker exec "$id" sh -c 'touch /tmp/drain' 2>/dev/null || true
  sleep "${DRAIN_SLEEP}"
  docker network disconnect "${FRONT_NET}" "$id" 2>/dev/null || true
  sleep 2
}

if [[ "${SKIP_PULL}" != "1" ]]; then
  compose pull api || docker pull "${REGISTRY}/shopapi:${VERSION}"
fi

# Base : N réplicas healthy.
compose up -d --scale "api=${REPLICAS}" --no-deps api
wait_healthy "${REPLICAS}"

OLD="$(api_ids)"
n_old=$(echo "$OLD" | grep -c . || true)
echo "réplicas à remplacer: ${n_old}"

# Start-first : on double le pool pour avoir N nouveaux à côté des anciens.
target=$((REPLICAS + n_old))
echo "-- scale start-first → ${target} --"
compose up -d --scale "api=${target}" --no-deps api
wait_healthy "${target}"

for id in $OLD; do
  name=$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')
  echo "-- retrait ${name} (${id:0:12}) --"
  drain "$id"
  docker stop -t 15 "$id"
  docker rm -f "$id" >/dev/null
  # Après chaque retrait on garde au moins REPLICAS healthy.
  wait_healthy "${REPLICAS}"
  echo "  ok après retrait de ${name}"
done

# Stabilise à N.
compose up -d --scale "api=${REPLICAS}" --no-deps api
wait_healthy "${REPLICAS}"

if compose config --services 2>/dev/null | grep -qx worker; then
  if [[ "${SKIP_PULL}" != "1" ]]; then
    compose pull worker 2>/dev/null || true
  fi
  compose up -d --no-deps worker || true
fi

echo "== rolling update terminé : shopapi:${VERSION} =="
compose ps api
