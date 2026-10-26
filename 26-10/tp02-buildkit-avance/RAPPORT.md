# Rapport TP02 — BuildKit, shop-worker

Dockerfile livré : `starter/shop-worker/Dockerfile`.
Bake : `docker-bake.hcl` à la racine du TP.
Les commandes `docker build` partent de `starter/shop-worker`. Les commandes `docker buildx bake` partent de `tp02-buildkit-avance`.

Machine : Docker 29.8.2, BuildKit v0.33.1, hôte `x86_64`. Pas de dépôt git exploitable pour un SHA court au moment des builds, donc `GIT_SHA=local`.

## 1. Fuite du secret en ARG

Le Dockerfile d'origine :

```dockerfile
ARG PIP_INDEX_URL=https://user:password@pypi.internal.example.com/simple
RUN pip install -r requirements-dev.txt
```

Build demandé par le sujet :

```bash
docker build --build-arg PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple -t worker:leak .
```

Il échoue : `pypi.internal.example.com` n'existe pas, l'image n'est pas taguée, `docker history worker:leak` répond `No such image`. Dans le log, pip masque le mot de passe (`https://svc-ci:****@...`), mais ce masque ne couvre que la sortie de pip.

Pour avoir une image et lire les métadonnées, j'ai reconstruit le même mécanisme (ARG + ENV + un fichier écrit avec la variable), puis j'ai supprimé l'image. Trois endroits :

1. **`docker history`**. BuildKit enregistre la valeur résolue sur l'instruction, même si le Dockerfile écrit `$PIP_INDEX_URL` :

```text
ARG PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple
ENV PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple
RUN |1 PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple /bin/sh -c ...
```

Le préfixe `|1 PIP_INDEX_URL=...` est ajouté par BuildKit sur tout `RUN` qui voit cet ARG. Le Dockerfile d'origine n'a pas d'`ENV`, et le secret est quand même dans cette ligne.

2. **`docker inspect`**. Le JSON d'inspection reprend ce `created_by`. Avec un `ENV PIP_INDEX_URL=$PIP_INDEX_URL`, `Config.Env` contient en plus la valeur en clair :

```text
PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple
```

3. **La couche**. Le `RUN` a écrit l'URL dans `/tmp/pip-url.txt`. `docker run --rm worker:leak cat /tmp/pip-url.txt` affiche le mot de passe. Un `pip install` qui aurait réussi laisserait la même information dans le cache HTTP de pip, dans la couche.

L'image de preuve a été supprimée (`docker rmi worker:leak`).

## 2. Secret mount

`pip.conf` local, ignoré par git et par le contexte de build :

```ini
[global]
index-url = https://pypi.org/simple
```

Le `RUN` ne reçoit plus d'ARG. Le fichier n'existe que le temps de l'instruction :

```dockerfile
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    pip install -r requirements.txt
```

```bash
docker build --secret id=pipconf,src=pip.conf --build-arg APP_VERSION=1.0 --build-arg GIT_SHA=local -t worker:1.0 .
```

Vérification :

```text
docker history --no-trunc worker:1.0 | grep -i secret   # aucune ligne
docker run --rm worker:1.0 cat /etc/pip.conf            # No such file or directory
docker run --rm worker:1.0 id                           # uid=1000(worker)
docker run --rm --entrypoint pip worker:1.0 list        # redis, psycopg2-binary, prometheus_client
                                                        # pas pytest, pas ruff
```

Image : 218 Mo sur le disque, 53,3 Mo de contenu. Les tests passent dans le stage `test` (2 passed, `ruff` : All checks passed) parce que le stage `runtime` copie le code depuis `test`. Le venv copié en prod vient du stage `builder`, donc sans les dépendances de dev.

Deux autres façons de ne pas laisser un secret dans l'image :

- **Dépôt Git privé** : `RUN --mount=type=ssh pip install git+ssh://git@github.com/org/prive.git`. Build avec `docker build --ssh default`. L'agent SSH de la machine est forwarded uniquement pour ce `RUN`. La clé n'est pas copiée dans une couche.
- **Variable d'environnement** : `docker build --secret id=TOKEN,env=TOKEN`. Dans le Dockerfile, `RUN --mount=type=secret,id=TOKEN` expose un fichier (`/run/secrets/TOKEN` par défaut), pas un `ENV`. Un `ENV` resterait dans `docker inspect` et dans `ps` des processus fils. Le fichier disparaît à la fin du `RUN`, et BuildKit masque la valeur dans les logs.

## 3. Cache de couches et cache mount

| Build | Durée | pip |
| --- | --- | --- |
| Premier build, cache vide | 28,1 s | télécharge redis, psycopg2-binary, prometheus-client, puis pytest et ruff |
| `docker builder prune -f`, mêmes requirements | 19,1 s | re-télécharge tout |
| `requests==2.32.3` ajouté, sans prune | 15,5 s | `Using cached` pour les trois paquets d'origine, télécharge seulement requests et ses dépendances |
| `--no-cache`, requirements encore avec requests | 16,3 s | re-télécharge tous les wheels |
| Retour aux requirements d'origine | 4,8 s | couche en cache |

`requests` a été retiré de `requirements.txt` après la mesure. L'image `worker:1.0` ne le contient pas.

Le cache de couches est le résultat d'une instruction (`RUN`, `COPY`). La clé dépend du texte de l'instruction et des fichiers qu'elle consomme. Changer `requirements.txt` invalide le `pip install`, même si les wheels sont déjà sur le disque.

Le cache mount est un répertoire (`/root/.cache/pip`) réinjecté à chaque `RUN`, identifié ici par `pip-${TARGETARCH}`. Il survit à un changement de couche : c'est le build avec `requests` qui le montre. pip réinstalle, mais les wheels déjà vus sortent en `Using cached`.

`--no-cache` et `docker builder prune -f` ne se comportent pas comme le commentaire du sujet sur cette version. `prune -f` a annoncé `Total: 3.709GB` et le build suivant a tout re-téléchargé : les cache mounts font partie du cache BuildKit, ils partent avec. `--no-cache` a aussi rejoué le `RUN` et pip a re-téléchargé les wheels. Le mount n'a pas été réutilisé. Le cas utile, mesuré ici, est l'invalidation de couche sans prune.

## 4. Multi-architecture

Builder dédié, sans changer le builder par défaut (`desktop-linux` reste actif) :

```bash
docker buildx create --name shop --driver docker-container
docker buildx inspect --bootstrap shop
docker buildx build --builder shop --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf \
  --build-arg APP_VERSION=1.0 --build-arg GIT_SHA=local \
  --provenance=true --sbom=true \
  -t shop-worker:1.0 \
  -o type=oci,dest=/tmp/tp02-worker-oci .
```

Durée totale : **144,7 s**. Les deux plateformes tournent en parallèle. Le détail :

| Étape | linux/amd64 (native) | linux/arm64 (QEMU) |
| --- | --- | --- |
| `python -m venv` | 4,7 s | 57,8 s |
| `pip install -r requirements.txt` | 2,4 s | 23,6 s |
| stage test (pytest + ruff) | 4,1 s, pytest 0,09 s | 40,3 s, pytest 0,92 s |
| cache mount | `id=pip-amd64` | `id=pip-arm64` |
| wheel psycopg2 | `manylinux2014_x86_64` | `manylinux2014_aarch64` |

`--push` ou `-o` est obligatoire parce qu'une image multi-plateforme n'est pas une image, c'est un **index** (manifest list) qui pointe vers une image par architecture. Le store Docker local chargé par `--load` ne sait stocker qu'une seule image pour un tag. Avec deux plateformes, l'exporter `docker` refuse l'index. `--push` l'envoie à un registre. `-o type=oci` l'écrit dans un tar (ici 106 Mo).

Le manifest list (`application/vnd.oci.image.index.v1+json`, digest `sha256:d53c422e3755…`) contient :

- une image `linux/amd64` (`sha256:2aea0cee854d…`)
- une image `linux/arm64` (`sha256:de2681542db4…`)
- deux manifests d'attestation (provenance SLSA + SBOM SPDX), un par plateforme

`TARGETARCH` est un ARG automatique (`amd64` ou `arm64`). Il sert d'id au cache mount : `pip-${TARGETARCH}`. Les wheels ne sont pas interchangeables, et deux builds parallèles qui partageraient le même répertoire se marcheraient dessus. Le log montre bien deux ids et deux noms de wheel.

L'arm64 est plus lent sur cette machine parce que le CPU est amd64 : QEMU traduit chaque instruction. Le `venv` passe de 4,7 s à 57,8 s. L'alternative est un builder avec un nœud natif par architecture, par exemple un runner Graviton ajouté au builder :

```bash
docker buildx create --name shop --append --platform linux/arm64 ssh://user@graviton
```

Chaque nœud ne build alors que sa plateforme. On peut aussi builder séparément et assembler l'index avec `docker buildx imagetools create`.

## 5. Cache distant

```bash
docker buildx build \
  --cache-from type=registry,ref=localhost:5000/cache:worker,mode=max \
  --cache-to type=registry,ref=localhost:5000/cache:worker,mode=max \
  ...
```

Le registre `localhost:5000` du TP03 n'était pas démarré. Le bake utilise donc un cache **local** (`tmp/bake-cache`, gitignoré) pour que `bake --load` fonctionne ici. En CI on remplace les deux lignes de `_common` par le `type=registry` ci-dessus, ou :

- `type=gha` : le cache est celui de GitHub Actions. Les runners n'ont pas de disque commun, l'action `docker/build-push-action` branche ce backend toute seule.
- `type=s3` : même idée, le cache est un bucket. Utile pour GitLab, Jenkins, ou des runners Kubernetes.

`mode=min` n'exporte que les couches de l'image finale. `mode=max` exporte aussi les stages intermédiaires (`builder`, `test`). `max` prend plus de place et permet de réutiliser le `pip install` quand seul le stage final change. `min` ne suffit pas pour ça.

## 6. Bake

`docker-bake.hcl` :

- groupe `default` : `api` (Dockerfile du TP01) et `worker`
- cible abstraite `_common` : labels OCI, `linux/amd64` + `linux/arm64`, cache local `mode=max`, args `APP_VERSION` et `GIT_SHA`
- variables `VERSION`, `GIT_SHA`, `REGISTRY` (`localhost:5000` par défaut)
- `worker-test` : stage `test` seulement, une seule plateforme, export `docker`, sans cache registre

```bash
docker buildx bake --print
VERSION=1.0 GIT_SHA=local docker buildx bake worker-test
VERSION=1.0 docker buildx bake --set '*.platform=linux/amd64' --load worker
```

`worker-test` s'est chargé en `shop-worker:test` (5,1 s, couches déjà en cache, 2 tests déjà passés au build précédent). `--set '*.platform=linux/amd64'` ramène le groupe à une plateforme, sinon `--load` est refusé. Le premier `--load` avertit que `tmp/bake-cache/index.json` n'existe pas encore : l'export crée le cache, l'import sert au build suivant.

Le secret du worker est déclaré dans la cible :

```hcl
secret = ["id=pipconf,src=starter/shop-worker/pip.conf"]
```

## Bonus

**B1.** J'ai relancé un build avec `--network=none` après avoir cassé le cache de couche, le mount `pip-amd64` étant déjà rempli. pip 25.0.1 interroge quand même l'index : `Temporary failure in name resolution`, puis `No matching distribution found for redis==5.0.8`. Le mount évite de re-télécharger quand le réseau répond. Il ne remplace pas l'index. Pour un build vraiment coupé d'Internet il faudrait `pip install --offline`, ce qui échoue tant que le cache n'a pas été rempli. C'est le schéma d'une CI en zone isolée : un premier build sur un runner connecté, les suivants dans un réseau sans sortie.

**B2.** Le build multi-arch a été fait avec `--provenance=true --sbom=true`. L'index OCI contient les deux attestations. La provenance SLSA cite le secret par son id (`pipconf`) et les build-args `APP_VERSION` et `GIT_SHA`. Elle ne contient pas l'URL ni le mot de passe. C'est la différence avec un ARG : la valeur d'un secret mount n'entre pas dans l'attestation.

**B3.** Pas fait. `uv` changerait le dossier de cache (`/root/.cache/uv`) et le montage, pas le reste du Dockerfile.
