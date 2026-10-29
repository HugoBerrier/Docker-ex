# Rapport d'incident — préprod Shop SAS

**Heure de début** : 09:12 · **Heure de résolution** : 10:05 · **Impact** : préprod indisponible (`curl localhost:8081/products` en échec)

## Chronologie du diagnostic

| Heure | Symptôme observé | Commande / preuve | Hypothèse | Résultat |
|-------|------------------|-------------------|-----------|----------|
| 09:15 | Port 8081 déjà pris sur l'hôte | `lsof -iTCP:8081 -sTCP:LISTEN` → `exercice05-adminer` | Conflit de publication, pas la stack incident | Confirmé ; `docker stop exercice05-adminer` |
| 09:18 | `compose up` échoue au build | `docker compose config` / chemin `…/solution/apps/shopapi` | Chemin `solution/` inexistant | Confirmé ; corriger vers `apps/shopapi` |
| 09:20 | Idem pour init SQL | `ls …/solution/db/init.sql` | Même erreur de chemin | Confirmé ; `db/init.sql` |
| 09:25 | Front démarre mais conf nginx absente / invalide | `docker exec front ls -la /etc/nginx/conf.d` | Montage d'un **répertoire** `./nginx` sur le **fichier** `default.conf` | Confirmé ; monter `./nginx/default.conf` |
| 09:28 | `curl :8081` timeout / connection refused depuis l'hôte | `docker network inspect incident_public` → `Internal: true` | Réseau `public` `internal: true` isole aussi l'accès utile / la publication | Confirmé ; retirer `internal` sur `public` |
| 09:32 | Nginx renvoie 502 | `docker exec front wget -qO- http://localhost:3000` échoue | `proxy_pass http://localhost:3000` vise nginx lui-même | Confirmé ; `proxy_pass http://api:3000` |
| 09:35 | API crash / ne répond pas | `docker compose logs api` → `Cannot find module` / process exit | `command: node server.js` alors que le binaire est `src/server.js` | Confirmé ; `node src/server.js` |
| 09:38 | API up mais `/ready` db ko | `docker exec api getent hosts databse` → vide ; `getent hosts db` OK | Typo `databse` dans `DATABASE_URL` | Confirmé ; hôte `db` |
| 09:40 | API ne joint pas Postgres | `docker inspect api` → réseaux : `public` seul | API absente du réseau `backend` où vit `db` | Confirmé ; ajouter `backend` à l'API |
| 09:42 | Healthcheck db never healthy | `docker inspect db --format '{{json .State.Health}}'` | `pg_isready -U postgres` alors que l'user est `shop` | Confirmé ; `-U shop -d shop` |
| 09:45 | Redis injoignable, pas de cache | `getent hosts redis` depuis api ; `network_mode: host` sur redis | Redis hors réseau Compose + mdp absent de `REDIS_URL` | Confirmé ; réseau `backend` + `redis://:r3dis@redis:6379` |
| 09:48 | Compose refuse / conflit de noms | `container_name: api` + `deploy.replicas: 2` | Nom fixe incompatible avec plusieurs réplicas | Confirmé ; retirer `container_name` et `replicas` |
| 09:52 | Port API ≠ proxy | env `PORT: 8080` vs nginx `:3000` | Décalage de port | Confirmé ; `PORT=3000` aligné sur nginx |
| 10:00 | Second GET `/products` sans `X-Cache: HIT` | `curl -D- localhost:8081/products` | Redis auth / réseau encore faux | Corrigé après URL + réseau ; HIT au 2ᵉ appel |
| 10:05 | Stack saine | `docker compose ps` + `up -d --wait` | — | Tout `healthy` |

## Anomalies trouvées

| # | Fichier / service | Anomalie | Correction | Catégorie |
|---|-------------------|----------|------------|----------|
| 1 | `compose.yml` / api | Build `…/solution/apps/shopapi` inexistant | `…/apps/shopapi` | configuration |
| 2 | `compose.yml` / db | Bind `…/solution/db/init.sql` inexistant | `…/db/init.sql` | stockage |
| 3 | `compose.yml` / front | Bind `./nginx` (dir) → `default.conf` (fichier) | `./nginx/default.conf:…` | configuration |
| 4 | `nginx/default.conf` | `proxy_pass http://localhost:3000` | `http://api:3000` | réseau |
| 5 | `compose.yml` / public | `internal: true` sur le réseau exposé à l'hôte | Réseau `public` non internal | réseau |
| 6 | `compose.yml` / api | `command: node server.js` | `node src/server.js` | configuration |
| 7 | `compose.yml` / api | `DATABASE_URL` hôte `databse` | `db` | configuration |
| 8 | `compose.yml` / api | API uniquement sur `public`, DB sur `backend` | API jointe à `public` + `backend` | réseau |
| 9 | `compose.yml` / db | Healthcheck `-U postgres` | `-U shop -d shop` | cycle de vie |
| 10 | `compose.yml` / redis | `network_mode: host` | Réseau Compose `backend` | réseau |
| 11 | `compose.yml` / api | `REDIS_URL` sans mot de passe alors que `--requirepass` | `redis://:r3dis@redis:6379` | sécurité / config |
| 12 | `compose.yml` / api | `container_name` + `deploy.replicas: 2` | Suppression des deux | cycle de vie |
| 13 | `compose.yml` / api | `PORT: 8080` ≠ proxy nginx `:3000` | `PORT: 3000` | configuration |

## Pourquoi ça n'a pas été détecté avant ?

Plusieurs changements ont été poussés d'un coup sans `docker compose config`, sans `up --wait`, et sans smoke test (`/products` + en-tête `X-Cache`). Les healthchecks faux (`postgres` au lieu de `shop`) donnaient une illusion de stack « presque bonne ». Aucune revue du compose ni contrôle CI sur les chemins et le DNS (`databse`).

## Actions de prévention

1. **CI** : `docker compose config` + smoke test (`curl /products` deux fois, assert `X-Cache: HIT`) avant merge.
2. **Revue de code** obligatoire sur tout diff `compose.yml` / configs proxy (checklist réseau, DNS, secrets, chemins).
3. **Healthchecks réels** + `docker compose up -d --wait` en préprod ; alerte si un service n'est pas `healthy` sous 60 s.
