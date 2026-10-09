# Exercice Docker #3 — Rendu

Site web personnalisé servi par **NGINX** dans Docker.  
Conteneur : **`exercice03-nginx`** — **http://localhost:8080**

## Contenu du dossier

- `Dockerfile` — image basée sur `nginx:alpine`
- `html/index.html` — page d'accueil (« Hello World — Exercice 03 »)
- `exercice03-nginx.tar` — archive de l'image

## Commandes exécutées

```bash
cd 03_exercices_rendus/exercice-03

# Construire l'image
docker build -t exercice03-nginx .

# Lancer le conteneur (port hôte 8080 → port NGINX 80)
docker run -d --name exercice03-nginx -p 8080:80 exercice03-nginx
```

## Archive de l'image

```bash
docker load -i exercice03-nginx.tar
```

## Vérification

```bash
docker ps --filter name=exercice03-nginx
curl http://localhost:8080
# → HTTP 200 + page "Hello World — Exercice 03"
```

Ouvre ensuite : **http://localhost:8080**

## Note

Le conteneur `exercice02-2048` a été **arrêté** (pas supprimé) pour libérer le port 8080.  
Pour le relancer : `docker start exercice02-2048` (après avoir arrêté celui-ci).

## Nettoyage (optionnel)

```bash
docker rm -f exercice03-nginx
# docker rmi exercice03-nginx
```
