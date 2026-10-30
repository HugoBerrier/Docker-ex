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
