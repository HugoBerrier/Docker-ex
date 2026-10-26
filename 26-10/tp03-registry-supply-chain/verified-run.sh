#!/usr/bin/env bash
# verified-run.sh IMAGE [args docker run...]
# Refuse docker run si la signature cosign ne correspond pas au digest.
set -euo pipefail
IMAGE="${1:?usage: verified-run.sh IMAGE [docker run args...]}"
shift
ROOT="$(cd "$(dirname "$0")" && pwd)"
PUB="${COSIGN_PUB:-$ROOT/cosign.pub}"
REF="$IMAGE"
if [[ "$REF" == 127.0.0.1:* ]]; then
  REF="registry.local:${REF#127.0.0.1:}"
fi

if command -v cosign >/dev/null 2>&1; then
  COSIGN_PASSWORD="${COSIGN_PASSWORD-}" SSL_CERT_FILE="${SSL_CERT_FILE:-$ROOT/starter/registry/certs/ca.crt}" \
    cosign verify --key "$PUB" --insecure-ignore-tlog=true \
    --registry-username "${REGISTRY_USER:-ci}" \
    --registry-password "${REGISTRY_PASSWORD:-ci-push-2024}" \
    "$REF"
else
  docker run --rm \
    -e SSL_CERT_FILE=/certs/ca.crt \
    --add-host registry.local:host-gateway \
    -v "$(dirname "$PUB"):/keys:ro" \
    -v "$ROOT/starter/registry/certs/ca.crt:/certs/ca.crt:ro" \
    ghcr.io/sigstore/cosign/cosign:v2.4.1 \
    verify --key "/keys/$(basename "$PUB")" --insecure-ignore-tlog=true \
    --registry-username "${REGISTRY_USER:-ci}" \
    --registry-password "${REGISTRY_PASSWORD:-ci-push-2024}" \
    "$REF"
fi

exec docker run "$@" "$IMAGE"
