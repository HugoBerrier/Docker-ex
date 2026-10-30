#!/usr/bin/env bash
# Crée le docker context « preprod » vers un hôte SSH (collègue, VM, ou localhost).
# Prérequis serveur : user deploy ∈ groupe docker, docker installé, clé SSH,
# fichiers .env + secrets/ présents sur le serveur (jamais dans git).
set -euo pipefail

HOST="${1:-localhost}"
USER_NAME="${2:-deploy}"
CTX="${3:-preprod}"

echo "== docker context ${CTX} → ssh://${USER_NAME}@${HOST} =="

if docker context inspect "${CTX}" >/dev/null 2>&1; then
  docker context rm -f "${CTX}" >/dev/null
fi

docker context create "${CTX}" --docker "host=ssh://${USER_NAME}@${HOST}"
docker --context "${CTX}" info >/dev/null
docker --context "${CTX}" ps
echo "ok : DOCKER_CONTEXT=${CTX} docker compose ..."
echo
echo "Secrets en prod : scp/rsync manuels, agent Vault/SOPS, ou provisioning Ansible."
echo "Ils restent hors git ; seuls .env.example et secrets/*.example sont versionnés."
