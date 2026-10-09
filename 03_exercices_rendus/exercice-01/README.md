# Exercice Docker #1 — Rendu

Image créée : **`ubuntu-nginx`** (NGINX 1.28.3 sur Ubuntu).

## Commandes exécutées

```bash
# 1. Créer / démarrer un conteneur Ubuntu
docker run --name exercice01-ubuntu -it ubuntu bash

# 2–4. Dans le conteneur : mise à jour + installation NGINX
apt-get update
apt-get install -y nginx
nginx -v
exit

# 5–6. Sortir puis sauvegarder l'état en nouvelle image
docker commit exercice01-ubuntu ubuntu-nginx
```

## Archive de l'image

Fichier : `ubuntu-nginx.tar` (~71 Mo)

```bash
# Recharger l'image depuis l'archive
docker load -i ubuntu-nginx.tar
```

## Vérification

```bash
docker images ubuntu-nginx
docker run --rm ubuntu-nginx nginx -v
# → nginx version: nginx/1.28.3 (Ubuntu)
```

## Nettoyage (optionnel)

```bash
docker rm exercice01-ubuntu
# docker rmi ubuntu-nginx   # seulement si tu veux supprimer l'image
```
