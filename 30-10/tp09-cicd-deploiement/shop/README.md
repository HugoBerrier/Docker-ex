# shop — dépôt CI/CD (TP09)

Stack Shop SAS + pipeline + déploiement sans interruption.

## Démarrage local

```bash
cp .env.example .env
# renseigner secrets/db_password.txt et secrets/pip.conf (non versionnés)
docker compose up -d --wait
./smoke-test.sh
```

## CI

- GitHub Actions : `.github/workflows/ci.yml`
- Sans compte distant : `./ci-local.sh` (registre TP03 `127.0.0.1:5500`)

## Déploiement

```bash
./deploy/setup-context.sh localhost "$USER" preprod
VERSION=sha-<git-sha> REGISTRY=127.0.0.1:5500 DOCKER_CONTEXT=preprod ./deploy/rolling-update.sh
```

Mesure downtime :

```bash
# terminal 1
./deploy/measure-downtime.sh 40
# terminal 2 — naïf ou rolling
docker compose up -d --force-recreate api
# ou
VERSION=… ./deploy/rolling-update.sh
```

Détails et captures : [RAPPORT.md](./RAPPORT.md).
