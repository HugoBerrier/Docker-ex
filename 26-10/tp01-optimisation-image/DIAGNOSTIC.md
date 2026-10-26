# Diagnostic — image `shopapi:legacy`

Travail fait dans `starter/shopapi`, sans modifier `src/server.js`.
L'image a été construite avec le Dockerfile d'origine :

```bash
docker build -t shopapi:legacy .
```

Premier build : **1 min 43 s**. `docker build` affiche déjà
`JSONArgsRecommended` sur le `CMD` (ligne 15) : la forme shell est signalée.

## 1. Taille et performance

### 1. L'image pèse 1,09 Go

```text
$ docker image ls shopapi:legacy
IMAGE            ID             DISK USAGE   CONTENT SIZE
shopapi:legacy   f3d5ef9f45e7       1.09GB          286MB

$ docker inspect shopapi:legacy --format 'Size={{.Size}}'
Size=1093632877
```

Le contexte copié ne fait que 49,2 Ko (`COPY . /app` dans `docker history`).
Le poids vient de la base et des paquets, pas de l'API.

Impact : le registre sature, les pulls CI et les rolling updates sont lents.

### 2. `apt-get update` laisse les listes dans une couche

```text
RUN apt-get update                         81.4MB
$ docker run --rm shopapi:legacy du -sh /var/lib/apt/lists
78M    /var/lib/apt/lists
```

Le `RUN` suivant ne peut pas supprimer ces fichiers : ils sont figés dans la couche d'avant.
Même chose pour le cache des `.deb`. hadolint le signale (`DL3009`, `DL3059`).

Impact : ~80 Mo inutiles, poussés au registre à chaque build.

### 3. La toolchain de build est dans l'image de prod

```text
RUN apt-get install -y curl wget vim git build-essential python3    393MB
RUN apt-get install -y nodejs                                       173MB
ADD ubuntu rootfs                                                    87.7MB

$ docker run --rm shopapi:legacy sh -c 'command -v vim git wget curl gcc'
/usr/bin/vim
/usr/bin/git
/usr/bin/wget
/usr/bin/curl
/usr/bin/gcc
```

Node est installé par-dessus Ubuntu, en plus de `build-essential`. L'API n'a besoin ni de gcc, ni de vim, ni de git au runtime.

Impact : image énorme, et en cas de faille sur l'API un attaquant a déjà un compilateur et git sous la main.

### 4. Les dépendances de dev sont installées

```text
ENV NODE_ENV=development
RUN npm install -g nodemon          7.54MB
RUN npm install                     63.5MB

$ docker run --rm shopapi:legacy sh -c 'test -d node_modules/eslint && echo eslint_present; command -v nodemon'
eslint_present
/usr/bin/nodemon
```

`NODE_ENV=development` et un `npm install` sans `--omit=dev` installent `eslint` et `nodemon`. `nodemon` est en plus installé en global. hadolint `DL3016` : la version de nodemon n'est pas épinglée.

Impact : ~70 Mo de plus, et des outils de dev en production.

### 5. Un changement de code relance `npm install`

Ordre actuel : `COPY . /app` puis `RUN npm install`.
Docker hashe le contexte entier. Dès qu'un fichier change, la couche `COPY` est invalidée, et tout ce qui est après aussi.

Mesure :

```text
$ time docker build -t shopapi:legacy .          # rien n'a changé
1.203 total
#13 [9/9] RUN npm install
#13 CACHED

$ echo "// commentaire" >> src/server.js
$ time docker build -t shopapi:legacy .
14.450 total
#13 [9/9] RUN npm install
#13 DONE 9.0s
```

Le commentaire a été retiré ensuite. `src/server.js` est revenu à l'original.

Impact : en CI, un commit qui ne touche qu'un README ou une ligne de code repaye ~9 s d'install (le sujet parle de ~4 min : ici le réseau était déjà chaud, le mécanisme est le même).

### 6. Pas de `.dockerignore`

```text
$ docker run --rm shopapi:legacy ls -la /app
-rw-r--r--  .env
-rw-r--r--  Dockerfile
-rw-r--r--  dump-prod-2024.sql
drwxr-xr-x  node_modules
-rw-r--r--  package-lock.json
drwxr-xr-x  src
drwxr-xr-x  test
```

`COPY .` embarque tout le dossier. Le dump du starter ne fait que 47 octets (fichier simulé), mais un vrai `dump-prod-2024.sql` n'a rien à faire dans l'image. Le `.env` non plus.

`dive shopapi:legacy` (mode CI) donne une efficacité de 99,6 % et 4,0 Mo de fichiers dupliqués (`/var/log/dpkg.log`, status dpkg, cache npm). Ce chiffre ne voit que les doublons entre couches. Il ne compte pas vim, git ou les 393 Mo d'apt, qui ne sont présents qu'une fois. L'image peut être « efficace » pour dive et quand même beaucoup trop grosse.

## 2. Sécurité

### 7. Le process tourne en root

```text
$ docker run --rm shopapi:legacy id
uid=0(root) gid=0(root) groups=0(root)

$ docker inspect shopapi:legacy --format 'User=[{{.Config.User}}]'
User=[]
```

Aucun `USER` dans le Dockerfile. Un RCE sur Express donne root dans le conteneur.

### 8. Le mot de passe Postgres est dans la config de l'image

```text
$ docker run --rm shopapi:legacy env | grep -i -E 'secret|database'
DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop

$ docker history shopapi:legacy
ENV DATABASE_URL=postgres://shop:S3cret!@db.…    0B
```

Le secret est dans `ENV`, donc dans l'historique et dans `docker inspect`, même sans ouvrir un shell. Le supprimer dans un `RUN` plus bas ne l'enlèverait pas des métadonnées.

Impact : toute personne qui peut `docker pull` l'image récupère le mot de passe de la base.

### 9. Le `.env` local est copié dans l'image

```text
$ docker run --rm shopapi:legacy cat /app/.env
DATABASE_URL=postgres://shop:S3cret!@localhost:5432/shop
REDIS_URL=redis://localhost:6379
AWS_SECRET_ACCESS_KEY=AKIAFAKEFAKEFAKEFAKE
```

C'est le fichier « commité par erreur ». Il est dans le filesystem, en plus de l'`ENV` du Dockerfile.

### 10. Node est installé par `curl | bash`, versions non épinglées

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
RUN apt-get install -y nodejs
```

hadolint sur le Dockerfile d'origine (warnings) :

```text
DL3008 warning  Pin versions in apt get install.     (lignes 5 et 7)
DL4006 warning  Set the SHELL option -o pipefail     (ligne 6, le pipe vers bash)
DL3016 warning  Pin versions in npm.                 (ligne 8, nodemon)
DL3025 warning  Use arguments JSON notation for CMD  (ligne 15)
```

Infos en plus : `DL3009` (listes apt), `DL3015` (`--no-install-recommends`), `DL3059` (plusieurs `RUN` d'affilée).

La base `ubuntu:22.04` a un tag, mais les paquets apt et nodemon n'ont pas de version. Le script NodeSource est téléchargé et exécuté en root pendant le build : si ce script change, le build change avec lui.

Impact : build non reproductible, et un point d'attaque sur la chaîne de build.

## 3. Exploitabilité en prod

### 11. `CMD` en forme shell : l'arrêt coupe le process au bout du timeout

`server.js` gère déjà `SIGTERM` (`shutdown` ferme le serveur HTTP). Le Dockerfile ne lui transmet pas le signal.

```text
$ docker history shopapi:legacy
CMD ["/bin/sh" "-c" "npm start"]

$ docker inspect shopapi:legacy --format '{{json .Config.Cmd}}'
["/bin/sh","-c","npm start"]
```

PID 1 est `/bin/sh`, pas node. `sh -c` ne relaie pas `SIGTERM` au process enfant. Docker attend la fin du timeout, puis envoie `SIGKILL`.

```text
$ time docker stop api-legacy
3.384 total
exit=137

$ time docker stop --timeout 10 api-legacy
10.373 total
exit=137
```

137 = 128 + 9, donc SIGKILL. Le sujet parle de 10 s : c'est bien ce qu'on obtient avec `--timeout 10`. Sur ce Docker, le timeout par défaut est plus court (~3,3 s), le résultat est le même : le handler de `server.js` ne tourne pas.

Impact : pendant un rolling update, les requêtes en cours sont coupées. 30 s cumulées si plusieurs replicas s'arrêtent mal.

### 12. Pas de `HEALTHCHECK`

```text
$ docker inspect shopapi:legacy --format '{{json .Config.Healthcheck}}'
null
```

Le conteneur peut être « running » alors que Node n'écoute pas encore, ou plus. L'orchestrateur envoie du trafic quand même. `/health` existe dans le code, il n'est juste pas branché.

### 13. Les labels ne décrivent pas l'application

```text
$ docker inspect shopapi:legacy --format '{{json .Config.Labels}}'
{"org.opencontainers.image.version":"22.04"}
```

Le seul label est celui d'Ubuntu. On ne peut pas savoir quelle version de shopapi ni quel commit tourne.

## Ordre de couches qui évite de réinstaller

Le `npm install` doit être avant la copie du code, et ne dépendre que des fichiers de dépendances :

```text
FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./    # change rarement
RUN npm ci --omit=dev                      # cache tant que le lock ne bouge pas
COPY src ./src                             # un commit ne relance pas npm
USER 1000
CMD ["node", "src/server.js"]
```

C'est cette séparation qui est reprise dans le Dockerfile multi-stage (voir le rapport).
