#!/usr/bin/env bash
# release-gate.sh IMAGE [--push REGISTRY_IMAGE]
# Refuse la publication si la politique Shop SAS n'est pas respectée.
# Si elle passe et que --push est donné : push, signature cosign, attestation SBOM.
set -uo pipefail

IMAGE="${1:?usage: release-gate.sh IMAGE [--push REGISTRY_IMAGE]}"
PUSH=""
if [[ "${2:-}" == "--push" ]]; then
  PUSH="${3:?usage: release-gate.sh IMAGE --push REGISTRY_IMAGE}"
elif [[ -n "${2:-}" ]]; then
  echo "usage: release-gate.sh IMAGE [--push REGISTRY_IMAGE]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${COSIGN_KEY:-$ROOT/cosign.key}"
PUB="${COSIGN_PUB:-$ROOT/cosign.pub}"
SBOM="${SBOM_PATH:-$ROOT/sbom.json}"
failures=0

fail() {
  echo "REFUS: $*" >&2
  failures=$((failures + 1))
}

docker_sock() {
  if [[ -S /var/run/docker.sock ]]; then
    echo /var/run/docker.sock
  elif [[ -S "${HOME}/.docker/run/docker.sock" ]]; then
    echo "${HOME}/.docker/run/docker.sock"
  else
    echo /var/run/docker.sock
  fi
}

run_trivy() {
  local sock args=()
  if command -v trivy >/dev/null 2>&1; then
    trivy "$@"
    return
  fi
  sock="$(docker_sock)"
  args=(-v "${sock}:/var/run/docker.sock" -v "${HOME}/Library/Caches/trivy:/root/.cache/" )
  docker run --rm "${args[@]}" aquasec/trivy:0.58.1 "$@"
}

run_syft() {
  local sock
  if command -v syft >/dev/null 2>&1; then
    syft "$@"
    return
  fi
  sock="$(docker_sock)"
  docker run --rm -v "${sock}:/var/run/docker.sock" anchore/syft:v1.18.1 "$@"
}

run_cosign() {
  if command -v cosign >/dev/null 2>&1; then
    COSIGN_PASSWORD="${COSIGN_PASSWORD-}" SSL_CERT_FILE="${SSL_CERT_FILE:-$ROOT/starter/registry/certs/ca.crt}" cosign "$@"
    return
  fi
  docker run --rm \
    -e COSIGN_PASSWORD="${COSIGN_PASSWORD-}" \
    -e SSL_CERT_FILE=/certs/ca.crt \
    -v "$(dirname "$KEY"):/keys:ro" \
    -v "$(dirname "$SBOM"):/sbom" \
    -v "$ROOT/starter/registry/certs/ca.crt:/certs/ca.crt:ro" \
    --add-host registry.local:host-gateway \
    ghcr.io/sigstore/cosign/cosign:v2.4.1 "$@"
}

echo "== porte de release : ${IMAGE} =="

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  fail "image introuvable localement"
  echo "refusé (${failures} contrôle(s))" >&2
  exit 1
fi

labels=$(docker inspect "$IMAGE" --format '{{json .Config.Labels}}')
for key in org.opencontainers.image.version org.opencontainers.image.revision org.opencontainers.image.source; do
  value=$(jq -r --arg k "$key" '.[$k] // empty' <<<"$labels")
  if [[ -z "$value" || "$value" == "null" ]]; then
    fail "label absent : ${key}"
  else
    echo "ok  label ${key}=${value}"
  fi
done

user=$(docker inspect "$IMAGE" --format '{{.Config.User}}')
if [[ -z "$user" || "$user" == "0" || "$user" == "root" || "$user" == "0:0" ]]; then
  fail "processus root (User='${user:-<vide>}')"
else
  echo "ok  utilisateur ${user}"
fi

health=$(docker inspect "$IMAGE" --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{else}}null{{end}}')
if [[ "$health" == "null" || "$health" == "[]" ]]; then
  fail "HEALTHCHECK absent"
else
  echo "ok  HEALTHCHECK ${health}"
fi

echo "-- scan secrets --"
if ! run_trivy image --scanners secret --exit-code 1 --quiet "$IMAGE"; then
  fail "secret détecté dans l'image"
else
  echo "ok  aucun secret"
fi

echo "-- scan CVE HIGH/CRITICAL corrigibles --"
if ! run_trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --quiet "$IMAGE"; then
  fail "CVE HIGH ou CRITICAL corrigible"
else
  echo "ok  pas de CVE HIGH/CRITICAL corrigible"
fi

if [[ "$failures" -ne 0 ]]; then
  echo "refusé (${failures} contrôle(s))" >&2
  exit 1
fi

echo "accepté"
if [[ -z "$PUSH" ]]; then
  exit 0
fi

echo "== publication ${PUSH} =="
docker tag "$IMAGE" "$PUSH"
docker push "$PUSH"

echo "-- SBOM --"
run_syft "$IMAGE" -o spdx-json > "$SBOM"
echo "sbom : ${SBOM} ($(jq '.packages | length' "$SBOM") paquets)"

host="${PUSH%%/*}"
if [[ "$host" == *:* ]]; then
  registry_host="${host%%:*}"
else
  registry_host="$host"
fi

sign_key="$KEY"
predicate="$SBOM"
if ! command -v cosign >/dev/null 2>&1; then
  sign_key="/keys/$(basename "$KEY")"
  predicate="/sbom/$(basename "$SBOM")"
fi

# 127.0.0.1 dans un conteneur n'est pas l'hôte. Le certificat couvre registry.local.
COSIGN_IMAGE="$PUSH"
if [[ "$COSIGN_IMAGE" == 127.0.0.1:* ]]; then
  COSIGN_IMAGE="registry.local:${COSIGN_IMAGE#127.0.0.1:}"
fi
echo "-- signature --"
run_cosign sign --key "$sign_key" --tlog-upload=false --yes \
  --registry-username "${REGISTRY_USER:-ci}" \
  --registry-password "${REGISTRY_PASSWORD:-ci-push-2024}" \
  "$COSIGN_IMAGE"
echo "-- attestation SBOM --"
run_cosign attest --key "$sign_key" --type spdxjson --predicate "$predicate" --tlog-upload=false --yes \
  --registry-username "${REGISTRY_USER:-ci}" \
  --registry-password "${REGISTRY_PASSWORD:-ci-push-2024}" \
  "$COSIGN_IMAGE"
echo "publié et signé : ${PUSH}"
