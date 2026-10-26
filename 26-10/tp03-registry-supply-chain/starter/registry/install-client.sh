#!/usr/bin/env bash
# Installe la CA pour le client Docker et ajoute registry.local dans /etc/hosts.
set -euo pipefail
cd "$(dirname "$0")"
test -f certs/ca.crt

dest="${HOME}/.docker/certs.d/registry.local:5000"
mkdir -p "$dest"
cp certs/ca.crt "$dest/ca.crt"
echo "CA copiée dans $dest/ca.crt"

if [[ -d /etc/docker ]] || sudo -n mkdir -p /etc/docker/certs.d/registry.local:5000 2>/dev/null; then
  sudo mkdir -p /etc/docker/certs.d/registry.local:5000
  sudo cp certs/ca.crt /etc/docker/certs.d/registry.local:5000/ca.crt
  echo "CA copiée dans /etc/docker/certs.d/registry.local:5000/ca.crt"
else
  echo "sudo indisponible : /etc/docker/certs.d non modifié"
fi

if grep -q '[[:space:]]registry\.local\b' /etc/hosts 2>/dev/null; then
  echo "/etc/hosts contient déjà registry.local"
elif sudo -n true 2>/dev/null; then
  echo "127.0.0.1 registry.local" | sudo tee -a /etc/hosts >/dev/null
  echo "registry.local ajouté à /etc/hosts"
else
  echo "Ajoute cette ligne dans /etc/hosts : 127.0.0.1 registry.local"
  exit 1
fi
