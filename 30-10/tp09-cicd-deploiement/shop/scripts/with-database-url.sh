#!/bin/sh
# Construit DATABASE_URL depuis le secret Compose. Le code applicatif n'est pas modifié :
# il lit uniquement la variable d'environnement.
set -eu
pw=$(cat /run/secrets/db_password | tr -d '\n')
export DATABASE_URL="postgres://shop:${pw}@db:5432/shop"
# Pino attend debug/info. logging.basicConfig de Python n'accepte que DEBUG/INFO.
if [ "${1:-}" = "python" ] && [ -n "${LOG_LEVEL:-}" ]; then
  case "$LOG_LEVEL" in
    debug|info|warning|error|critical) LOG_LEVEL=$(printf '%s' "$LOG_LEVEL" | tr '[:lower:]' '[:upper:]'); export LOG_LEVEL ;;
  esac
fi
exec "$@"
