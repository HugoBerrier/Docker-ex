#!/usr/bin/env bash
# retention.sh REGISTRY REPO KEEP
# Garde tous les tags semver. Parmi les autres, garde les KEEP plus récents
# et supprime le reste. Un digest encore référencé par un tag conservé n'est pas supprimé.
#
# Exemple : ./retention.sh registry.local:5000 shopapi 5
# Auth    : REGISTRY_USER / REGISTRY_PASSWORD (défaut ci / ci-push-2024)
#           DRY_RUN=1 pour afficher sans supprimer
set -euo pipefail

REG="${1:?usage: retention.sh REGISTRY REPO KEEP}"
REPO="${2:?usage: retention.sh REGISTRY REPO KEEP}"
KEEP="${3:?usage: retention.sh REGISTRY REPO KEEP}"
USER_NAME="${REGISTRY_USER:-ci}"
PASSWORD="${REGISTRY_PASSWORD:-ci-push-2024}"
DRY="${DRY_RUN:-0}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
CA="${REGISTRY_CA:-$ROOT/starter/registry/certs/ca.crt}"

ACCEPT="application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json"
SEMVER='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$'

api() {
  curl -fsS --cacert "$CA" -u "${USER_NAME}:${PASSWORD}" "$@"
}

tags=$(api "https://${REG}/v2/${REPO}/tags/list" | jq -r '.tags[]?')
if [[ -z "${tags}" ]]; then
  echo "aucun tag sur ${REPO}"
  exit 0
fi

tmp=$(mktemp)
kept=$(mktemp)
trap 'rm -f "$tmp" "$kept"' EXIT

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  headers=$(api -sI -H "Accept: ${ACCEPT}" "https://${REG}/v2/${REPO}/manifests/${tag}")
  digest=$(awk 'tolower($1)=="docker-content-digest:" {print $2}' <<<"$headers" | tr -d '\r')
  manifest=$(api -H "Accept: ${ACCEPT}" "https://${REG}/v2/${REPO}/manifests/${tag}")
  config=$(jq -r '.config.digest // empty' <<<"$manifest")
  if [[ -z "$config" ]]; then
    child=$(jq -r '[.manifests[]? | select(.platform.os=="linux")][0].digest // .manifests[0].digest // empty' <<<"$manifest")
    if [[ -n "$child" ]]; then
      child_manifest=$(api -H "Accept: ${ACCEPT}" "https://${REG}/v2/${REPO}/manifests/${child}")
      config=$(jq -r '.config.digest // empty' <<<"$child_manifest")
    fi
  fi
  created="1970-01-01T00:00:00Z"
  if [[ -n "$config" ]]; then
    blob_created=$(api "https://${REG}/v2/${REPO}/blobs/${config}" | jq -r '.created // empty' || true)
    if [[ -n "$blob_created" ]]; then
      created="$blob_created"
    fi
  fi
  kind="floating"
  if [[ "$tag" =~ $SEMVER ]]; then
    kind="semver"
  fi
  printf '%s\t%s\t%s\t%s\n' "$created" "$kind" "$digest" "$tag" >> "$tmp"
done <<<"$tags"

echo "tags trouvés :"
sort -r "$tmp" | while IFS=$'\t' read -r created kind digest tag; do
  printf '  %-10s %-24s %s\n' "$kind" "$tag" "$created"
done

awk -F '\t' '$2=="semver"' "$tmp" >> "$kept"
awk -F '\t' '$2=="floating"' "$tmp" | sort -r | head -n "$KEEP" >> "$kept"

echo "suppression (hors semver, au-delà des ${KEEP} plus récents) :"
deleted=0
seen=$(mktemp)
trap 'rm -f "$tmp" "$kept" "$seen"' EXIT

while IFS=$'\t' read -r created kind digest tag; do
  [[ "$kind" == "semver" ]] && continue
  if awk -F '\t' -v t="$tag" '$4==t {found=1} END {exit !found}' "$kept"; then
    continue
  fi
  if awk -F '\t' -v d="$digest" '$3==d {found=1} END {exit !found}' "$kept"; then
    echo "  garde ${tag} : digest encore utilisé par un tag conservé"
    continue
  fi
  if grep -qx "$digest" "$seen"; then
    continue
  fi
  echo "$digest" >> "$seen"
  echo "  supprime ${tag} (${digest})"
  if [[ "$DRY" != "1" ]]; then
    api -X DELETE -H "Accept: ${ACCEPT}" "https://${REG}/v2/${REPO}/manifests/${digest}" >/dev/null
  fi
  deleted=1
done < <(sort "$tmp")

if [[ "$deleted" == "0" ]]; then
  echo "rien à supprimer"
fi
