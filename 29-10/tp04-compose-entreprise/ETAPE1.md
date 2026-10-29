# Étape 1 — problèmes de `starter/docker-compose.yml`

1. `version: '3'` est obsolète. La spécification Compose actuelle n'utilise plus cette clé.
2. `links` est un mécanisme hérité. Sur un réseau Compose, le nom du service suffit, et `links` n'attend pas que Postgres ou Redis acceptent des connexions.
3. `postgres` et `redis` ne sont pas épinglés. Un `pull` ultérieur peut changer la version majeure.
4. Les ports `5432` et `6379` sont publiés sur l'hôte. La base et Redis sont joignables en dehors du réseau Docker.
5. Le mot de passe `postgres` est en clair dans `POSTGRES_PASSWORD` et dans `DATABASE_URL`, donc dans un fichier versionné.
6. `sleep 10` avant `node` est une course. Si la base met plus de 10 s, l'API démarre quand même ; si elle est prête avant, on attend pour rien.
7. Un seul réseau implicite. Le proxy, l'API et la base se voient tous. Rien n'isole les données d'Internet.
8. Aucun healthcheck. `docker compose up --wait` ne peut pas savoir que la stack est saine.
9. Aucun volume nommé. Les données de Postgres disparaissent avec le conteneur.
10. `restart: always` est posé seulement sur le worker. L'API et la base ne redémarrent pas, et `always` relance le worker même après un arrêt volontaire (`unless-stopped` s'arrête avec le projet).
11. Pas de limite CPU ou mémoire, pas de rotation des logs.
12. L'API est exposée directement sur le port 3000, sans reverse proxy.

## Réponses vérifiées

**Étape 4, `--scale`.** Avec `compose.prod.yml` (`deploy.replicas: 2`) :

- `docker compose -f compose.yml -f compose.prod.yml up -d --scale api=3` crée un troisième conteneur (`shop-api-3`). `--scale` l'emporte sur le fichier pour cette commande.
- `docker compose -f compose.yml -f compose.prod.yml up -d` (sans `--scale`) supprime ce conteneur et revient à 2 réplicas, la valeur de `deploy.replicas`.

Les logs d'accès Traefik, sur six `GET /health`, alternent `172.24.0.3:3000` et `172.24.0.5:3000`. La charge est répartie. L'id du conteneur n'est pas ajouté à la réponse HTTP.

**B1.** L'étape 3 impose le bind mount et `node --watch`. Après une modification de `server.js`, les logs affichent `Restarting 'src/server.js'` puis un nouveau démarrage. Le fichier a été remis dans son état d'origine. `develop.watch` avec `sync` copie les fichiers dans le conteneur sans montage hôte ; `rebuild` reconstruit l'image. Le bind mount reste celui demandé par l'étape 3.

**B2.** TLS `mkcert` non mis en place : pas de certificats locaux ajoutés à la stack.

**B3.** Oui. Adminer est sur `front` et sur `back`. Traefik n'est que sur `front` (réseau public) et joint Adminer par là (`adminer.localhost` répond 200). Adminer joint Postgres par `back`. La base, elle, n'est que sur `back` (`internal: true`) : Traefik et l'extérieur ne l'atteignent pas.

**B4.** Sans `REGISTRY`, `docker compose -f compose.yml -f compose.prod.yml config` échoue :

`required variable REGISTRY is missing a value: REGISTRY doit être défini`

**B5.** `include:` permet de découper le fichier, mais une ancre YAML (`x-healthcheck-defaults`, `x-logging`) n'est pas visible d'un fichier inclus à l'autre. Les ancres restent dans le fichier de base unique.

**Image Traefik.** Le sujet demande `traefik:v3.1`. Cette version parle à Docker avec l'API 1.24. Docker Engine 29.8.2 refuse cette API (minimum 1.40) et Traefik ne lit plus aucun label. `traefik:v3.6.1` est la première version qui négocie l'API : `api.localhost` et le dashboard répondent.
