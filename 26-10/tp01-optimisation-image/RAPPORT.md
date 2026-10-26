# Rapport TP01 — image shopapi

Dockerfile livré : `starter/shopapi/Dockerfile`.
Contexte de build : `starter/shopapi`. Le code applicatif (`src/server.js`) n'a pas été modifié : le handler `SIGTERM` était déjà là, c'est le `CMD` shell qui l'empêchait de tourner.

Build utilisé :

```bash
docker build \
  --build-arg APP_VERSION=1.4.2 \
  --build-arg GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)" \
  -t shopapi:1.4.2 .

docker build --target test -t shopapi:test .
```

Pas de dépôt git dans le dossier, donc `GIT_SHA` vaut `local`.

## Avant / après

| Critère | Legacy | `shopapi:1.4.2` |
| --- | --- | --- |
| Taille (`docker image ls`, disk usage) | 1,09 Go | 175 Mo |
| Taille contenu | 286 Mo | 45,8 Mo |
| Couches (`docker history`) | 18 | 18 |
| Premier build (bases déjà présentes) | 1 min 43 s | 13,5 s |
| Rebuild sans changement de code | 1,2 s | 1,1 s |
| Rebuild après un commentaire dans `src/server.js` | 14,5 s, `npm install` relancé (9,0 s) | 2,5 s, `npm ci` en cache |
| Utilisateur | `uid=0(root)` | `uid=1000(node)` |
| `docker stop` | ~3,3 s, exit 137 ; 10,4 s avec `--timeout 10` | 0,22 s, exit 0 |
| Healthcheck | absent | `healthy` après 6 s |
| Secrets dans l'image | `DATABASE_URL` + fichier `.env` | aucun |
| Dev dependencies | eslint, nodemon | absentes |
| hadolint | 4 warnings | sortie vide |

Le nombre de couches ne baisse pas : l'image finale fait plusieurs `COPY` (binaire node, deux `.so`, `node_modules`, `package.json`, `src`) plus les couches d'Alpine. Le gain est le contenu des couches, pas leur nombre. On n'a plus les 393 Mo d'apt ni les 81 Mo de listes.

## Pourquoi `npm install` était rejoué

`COPY .` puis `RUN npm install` : le cache de Docker s'arrête à la première instruction dont le contenu change. Un commentaire dans `server.js` change le hash du `COPY`, donc `npm install` repart de zéro.

Dans le nouveau Dockerfile, `package.json` et `package-lock.json` sont copiés seuls, et `npm ci` est dans un `RUN` avant le code. Au rebuild après commentaire :

```text
#10 [test 4/7] RUN npm ci && npm cache clean --force
#10 CACHED
#11 [test 5/7] COPY src ./src
#11 DONE 0.0s
#13 [test 7/7] RUN npm test && npm run lint
#13 DONE 0.9s
#19 [deps 4/4] RUN npm ci --omit=dev && npm cache clean --force
#19 CACHED
```

`npm ci` ne tourne plus. Seuls la copie de `src/` et les tests (0,9 s) sont rejoués. Total : 2,5 s. Le commentaire a été retiré, puis l'image a été reconstruite pour qu'elle corresponde au source.

J'ai ajouté `package-lock.json` (généré avec le npm de `node:20-alpine`, lockfileVersion 3) pour que `npm ci` soit reproductible. Sans lockfile, `npm install` peut résoudre d'autres versions d'un build à l'autre.

## Ce que fait le Dockerfile

Trois stages :

```text
deps   npm ci --omit=dev          ── node_modules de prod ──┐
test   npm ci + npm test + lint   ── src vérifié ───────────┼── runtime
runtime  alpine 3.23.4 + binaire node (user 1000)  ◄────────┘
```

- **deps** : uniquement les dépendances de prod. Cette couche reste en cache tant que le lockfile ne change pas.
- **test** : `npm test` et `npm run lint`. Le stage `runtime` copie `src/` depuis `test`, donc un `docker build` normal échoue si les tests échouent. `docker build --target test` passe aussi (1 test ok, `lint ok`).
- **runtime** : l'image qu'on déploie. Pas de npm, pas de headers, pas des devDependencies.

`node:20-alpine` complet + les `node_modules` donnait **211 Mo**, au-dessus de la limite de 200 Mo. Le binaire `node` fait 97 Mo, le reste de l'image officielle c'est surtout npm, yarn et les headers. Je suis donc parti d'`alpine:3.23.4`, qui est la version d'Alpine de `node:20-alpine` (`/etc/alpine-release`), et j'ai copié :

- `/usr/local/bin/node`
- `libstdc++.so.6` et `libgcc_s.so.1` (`ldd` sur le binaire)

musl est déjà dans Alpine. `id` et `ls` du sujet fonctionnent (busybox). L'utilisateur `node` est créé avec l'uid 1000, comme sur l'image officielle. hadolint `DL3066` (info) râle si on écrit `--chown=node:node`, d'où l'uid numérique. `docker run --rm shopapi:1.4.2 id` affiche quand même `uid=1000(node)`.

`.dockerignore` exclut `node_modules`, `.git`, `.env`, `*.sql` et les logs. Le Dockerfile ne fait de toute façon pas de `COPY .` : il ne prend que le lockfile, `package.json`, `src/` et `test/`.

`CMD ["node", "src/server.js"]` est en forme exec. Node est PID 1 (`"pid":1` dans les logs) et reçoit `SIGTERM`. Au `docker stop` :

```text
{"signal":"SIGTERM","msg":"arrêt demandé"}
docker stop api   0.222 total
exit=0
```

Le process sort tout seul, Docker n'a pas besoin d'envoyer SIGKILL.

`HEALTHCHECK` appelle `http://127.0.0.1:3000/health` avec `fetch` (Node 20), parce qu'il n'y a pas wget. Intervalle 3 s : après `sleep 6`, l'état est `healthy`. `GET /products` renvoie les 3 produits, `GET /` renvoie `"version": "1.4.2"` (`APP_VERSION` vient du build-arg).

Labels :

```json
{
  "org.opencontainers.image.version": "1.4.2",
  "org.opencontainers.image.revision": "local",
  "org.opencontainers.image.source": "https://git.shop-sas.local/platform/shopapi"
}
```

## hadolint

```bash
docker run --rm -i hadolint/hadolint < Dockerfile
echo $?
```

Sortie vide, code de sortie 0.

## Dockerfile final

```dockerfile
# Image finale : dépendances de prod seulement, process non-root.
# Le code est copié après npm ci pour ne pas casser le cache à chaque commit.

FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Étape dédiée aux tests. Elle n'est pas l'image de prod :
# le stage runtime recopie src depuis ici, donc un `docker build`
# normal échoue si npm test ou npm run lint échoue.
FROM node:20-alpine AS test
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci && npm cache clean --force
COPY src ./src
COPY test ./test
RUN npm test && npm run lint

# node:20-alpine embarque npm, yarn et les headers (~190 Mo avant notre code).
# Avec les node_modules on dépassait 200 Mo. On repart d'alpine 3.23.4
# (la même que node:20-alpine) et on ne copie que le binaire node + ses .so.
FROM alpine:3.23.4 AS runtime
RUN addgroup -g 1000 node && adduser -u 1000 -G node -s /bin/sh -D node
WORKDIR /app

ARG APP_VERSION=dev
ARG GIT_SHA=local

LABEL org.opencontainers.image.title="shopapi" \
      org.opencontainers.image.description="API catalogue produits" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.source="https://git.shop-sas.local/platform/shopapi"

ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION}

COPY --from=deps /usr/local/bin/node /usr/local/bin/node
COPY --from=deps /usr/lib/libstdc++.so.6.0.34 /usr/lib/libstdc++.so.6
COPY --from=deps /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1

# 1000 est l'uid du user "node" créé plus haut.
# Un nom (node:node) laisse un info hadolint DL3066.
COPY --from=deps --chown=1000:1000 /app/node_modules ./node_modules
COPY --chown=1000:1000 package.json ./
COPY --from=test --chown=1000:1000 /app/src ./src

USER 1000
EXPOSE 3000

# Pas de wget dans l'image. Le healthcheck appelle /health avec node.
# Intervalle 3s pour être healthy après le sleep 6 du sujet.
HEALTHCHECK --interval=3s --timeout=2s --start-period=2s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

# Forme exec : node est PID 1 et reçoit SIGTERM (arrêt propre dans server.js).
CMD ["node", "src/server.js"]
```

## Bonus (pas implémentés, juste notés)

**B1 distroless.** Je ne l'ai pas construit. Le compromis : pas de shell, donc `docker run … id` et `ls /app` du sujet ne marchent plus, et on ne peut plus ouvrir un shell pour débugger. Le healthcheck sans wget est le même que celui de l'image actuelle : `node -e "fetch(...)"`, puisque l'image distroless node contient le binaire node.

**B2 cache mount.** Le cas « je change une ligne de code » est déjà réglé par l'ordre des couches (`npm ci` en cache, 2,5 s). Un `--mount=type=cache,target=/root/.npm` sert surtout au build `--no-cache`, quand la couche `npm ci` est invalidée mais que les paquets sont encore sur le disque du builder. Je n'ai pas chronométré les deux.

**B3 digest identique.** Deux builds d'affilée ne donnent en général pas le même digest : les timestamps des couches changent, et `node:20-alpine` est un tag qui bouge. Pour figer ça il faudrait un digest d'image de base, `SOURCE_DATE_EPOCH`, et un export OCI avec `rewrite-timestamp=true`. Pas fait ici.
