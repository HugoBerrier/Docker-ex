# TP09 — CI/CD : PR → déploiement sans interruption

## Livrables

| Élément | Chemin |
|--------|--------|
| Pipeline GitHub Actions | `.github/workflows/ci.yml` |
| Simulation locale | `ci-local.sh` |
| Mesure downtime | `deploy/measure-downtime.sh` |
| Rolling update | `deploy/rolling-update.sh` |
| Context SSH | `deploy/setup-context.sh` |
| Captures | `transcripts/` |
| Bonus Swarm | `compose.swarm.yml` |

## 1. Dépôt `shop`

Assemblage : apps TP01/02, stack compose TP04, `release-gate.sh` TP03.
Secrets (`.env`, `secrets/db_password.txt`, `secrets/pip.conf`) **hors git** ; `secrets/pip.conf.ci` est versionné pour le build worker en CI.

## 2. Pipeline

### Pull request
- hadolint sur les Dockerfiles
- `docker compose -f compose.yml -f compose.prod.yml config`
- build de l’étape `test` (matrice api / worker)
- build multi-arch de l’image **sans push**
- cache `type=gha`, `docker/metadata-action`, `provenance` + `sbom`

### Push `main`
- push tags `sha-<sha>` (politique TP03, jamais `latest`)
- Trivy bloquant HIGH/CRITICAL
- Cosign **keyless** (OIDC)
- déploiement préprod automatique (`environment: preprod`) via `rolling-update.sh`

### Tag `v*`
- tags semver via metadata-action
- `environment: production` → **approbation manuelle**
- vérification de signature cosign avant rolling prod

Sans compte GitHub : `./ci-local.sh` rejoue build → push registre TP03 → release-gate → rolling.
`act` peut exécuter le workflow en conteneur.

## 3. Déploiement distant (`docker context`)

```bash
./deploy/setup-context.sh preprod.local deploy preprod
# ou sur la même machine :
./deploy/setup-context.sh localhost "$(whoami)" preprod
DOCKER_CONTEXT=preprod VERSION=sha-<sha> REGISTRY=ghcr.io/<org> ./deploy/rolling-update.sh
```

### Prérequis serveur
- utilisateur `deploy` dans le groupe `docker`
- clé SSH (agent ou `DEPLOY_SSH_KEY` en secret CI)
- Docker Engine + Compose plugin
- dépôt (ou artefact) présent, avec **`.env` + `secrets/` sur le serveur uniquement**

### Comment les secrets arrivent en prod
Pas via git. Options : `scp`/`rsync` initial, Ansible/Vault, SOPS, sealed secrets. La CI ne transporte que `VERSION` / `REGISTRY` ; les fichiers secrets restent déjà sur l’hôte.

## 4. Zéro interruption — mesures

Charge : ~100 req/s sur `GET /health` (`Host: api.localhost` → `127.0.0.1`).

| Scénario | ok | **fail** | req/s | Capture |
|----------|-----|----------|-------|---------|
| Naïf (`compose up -d --force-recreate api`, 1 réplica) | 2621 | **1167** | 94.7 | `transcripts/naive-downtime.txt` |
| Rolling start-first (2+ réplicas, drain `/lb-ready`) | 8625 | **39** | 96.3 | `transcripts/rolling-downtime.txt` |
| Baseline stable (pas de deploy) | 831 | **0** | 103.9 | `transcripts/baseline-measure.txt` |

Le rolling réduit les échecs d’un facteur ~30. Les ~39 résiduels (timeouts ~0,4 s) correspondent à la course Traefik/Docker Desktop au moment du `network disconnect` / `stop` ; Swarm `start-first` (bonus) les élimine nativement.

### Rôle de chaque brique

| Brique | Rôle | Si on la retire |
|--------|------|-----------------|
| `HEALTHCHECK` image + compose | Docker ne déclare healthy qu’après boot | Traefik peut router trop tôt → 502 |
| `/lb-ready` + label Traefik healthcheck | Readiness LB : drain sans casser `/health` | Impossible de retirer un backend proprement |
| `start_period` | Tolère le démarrage froid | Conteneur tué / marqué unhealthy trop tôt |
| SIGTERM + `stop_grace_period: 15s` | Draine les connexions in-flight (TP01) | Coupure brutale mid-request |
| `--wait` / wait healthy | Gate avant de basculer le suivant | Chevauchement unhealthy |
| Réplicas ≥ 2 | Toujours un backend vivant | Indisponibilité totale au recreate |
| Proxy Traefik + retry | LB + 3 retries | Un backend down = erreur client |
| `/tmp/drain` | Readiness rouge avant stop | Traefik continue d’envoyer du trafic pendant le stop |

## 5. Rollback

```bash
VERSION=<ancien-sha> ./deploy/rolling-update.sh
```

Durée mesurée : **30 s** (`transcripts/rollback.txt`).

### Ce qui rend le rollback possible
- tags **immuables** (`sha-…`, semver) — pas de `latest`
- images encore présentes sur l’hôte / le registre
- schéma DB **rétro-compatible** (expand/contract)

### Migration non rétro-compatible
Un rollback d’image seul casse (nouvelle colonne NOT NULL absente de l’ancien code, etc.). Il faut : migration expand → déployer code → contract ; ou rollback DB + image dans le même créneau, avec backup TP05.

## Bonus

- **B1** `compose.swarm.yml` : `update_config.order=start-first` + `rollback_config`. Moins de script, plus robuste ; exige Swarm.
- **B2** GitOps pull (watchtower / cron `compose pull && up -d`) : pas d’SSH entrant ; risques `latest`, pas de gate signature.
- **B3** / **B4** : non implémentés dans ce rendu (piste : `docker compose publish`, job CI `up --wait` + `smoke-test.sh`).
