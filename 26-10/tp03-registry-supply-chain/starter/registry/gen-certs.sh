#!/usr/bin/env bash
# CA interne + certificat serveur. SAN : registry.local, localhost, registry.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p certs
if [[ -f certs/registry.crt && -f certs/ca.crt && "${1:-}" != "--force" ]]; then
  echo "certs déjà présents (gen-certs.sh --force pour régénérer)"
  exit 0
fi

openssl genrsa -out certs/ca.key 4096
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 825 \
  -out certs/ca.crt -subj "/CN=Shop SAS Internal CA"

openssl genrsa -out certs/registry.key 2048
openssl req -new -key certs/registry.key -out certs/registry.csr \
  -subj "/CN=registry.local"

cat > certs/san.cnf << 'EOF'
subjectAltName = DNS:registry.local, DNS:localhost, DNS:registry, IP:127.0.0.1
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl x509 -req -in certs/registry.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -CAcreateserial -out certs/registry.crt -days 825 -sha256 \
  -extfile certs/san.cnf
rm -f certs/registry.csr
echo "CA et certificat serveur écrits dans certs/"
openssl x509 -in certs/registry.crt -noout -ext subjectAltName
