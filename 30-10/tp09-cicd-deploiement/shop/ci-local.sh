#!/usr/bin/env bash
# Rejoue localement les étapes du pipeline contre le registre du TP03 (127.0.0.1:5500).
# Remplace GitHub Actions quand le compte GH/GL n'est pas dispo. Compatible `act`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

REGISTRY="${REGISTRY:-127.0.0.1:5500}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
FULL_SHA="$(git rev-parse HEAD 2>/dev/null || echo local)"
VERSION="sha-${FULL_SHA}"
SHORT_TAG="sha-${SHA}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
# Sur Mac arm : PLATFORMS=linux/arm64 ou multi via buildx.

export REGISTRY_USER="${REGISTRY_USER:-ci}"
export REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-ci-push-2024}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-}"

echo "== ci-local : ${VERSION} → ${REGISTRY} =="

echo "-- hadolint --"
if command -v hadolint >/dev/null 2>&1; then
  hadolint apps/shopapi/Dockerfile apps/shop-worker/Dockerfile || true
else
  docker run --rm -i hadolint/hadolint:2.12.0-alpine < apps/shopapi/Dockerfile || true
  docker run --rm -i hadolint/hadolint:2.12.0-alpine < apps/shop-worker/Dockerfile || true
fi

echo "-- compose config --"
REGISTRY=dummy VERSION=dummy docker compose -f compose.yml -f compose.prod.yml config >/dev/null
echo "ok compose config"

echo "-- login registry --"
echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin

build_one() {
  local ctx="$1" name="$2" secret_args=()
  if [[ "$name" == "shop-worker" ]]; then
    secret_args=(--secret "id=pipconf,src=${ROOT}/secrets/pip.conf")
    if [[ ! -f "${ROOT}/secrets/pip.conf" ]]; then
      secret_args=(--secret "id=pipconf,src=${ROOT}/secrets/pip.conf.ci")
    fi
  fi

  echo "-- build test stage ${name} --"
  docker buildx build "${secret_args[@]}" --target test --load -t "${name}:test" "${ctx}"

  echo "-- build + push ${name} (${PLATFORMS}) --"
  local dest="${REGISTRY}/${name}:${VERSION}"
  local dest_short="${REGISTRY}/${name}:${SHORT_TAG}"
  docker buildx build "${secret_args[@]}" \
    --platform "${PLATFORMS}" \
    --build-arg "APP_VERSION=dev" \
    --build-arg "GIT_SHA=${FULL_SHA}" \
    --label "org.opencontainers.image.title=${name}" \
    --label "org.opencontainers.image.version=dev" \
    --label "org.opencontainers.image.revision=${FULL_SHA}" \
    --label "org.opencontainers.image.source=https://git.shop-sas.local/platform/${name}" \
    --provenance=true \
    --sbom=true \
    -t "${dest}" -t "${dest_short}" \
    --push \
    "${ctx}" || {
      # fallback mono-arch load+push si buildx push multi échoue sans registry buildkit
      docker build "${secret_args[@]}" \
        --build-arg "APP_VERSION=dev" \
        --build-arg "GIT_SHA=${FULL_SHA}" \
        --label "org.opencontainers.image.title=${name}" \
        --label "org.opencontainers.image.version=dev" \
        --label "org.opencontainers.image.revision=${FULL_SHA}" \
        --label "org.opencontainers.image.source=https://git.shop-sas.local/platform/${name}" \
        -t "${dest}" -t "${dest_short}" "${ctx}"
      docker push "${dest}"
      docker push "${dest_short}"
    }

  echo "-- release-gate + cosign ${name} --"
  if [[ -x ./release-gate.sh ]]; then
    ./release-gate.sh "${dest}" --push "${dest}" || ./release-gate.sh "${dest}"
  fi
}

build_one apps/shopapi shopapi
build_one apps/shop-worker shop-worker

echo "-- déploiement préprod local (rolling) --"
VERSION="${VERSION}" REGISTRY="${REGISTRY}" ./deploy/rolling-update.sh

echo "== ci-local OK : ${VERSION} =="
