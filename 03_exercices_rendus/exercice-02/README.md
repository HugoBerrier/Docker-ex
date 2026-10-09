# Exercice Docker #2 — Rendu

Image utilisée : **`kubespheredev/2048`** (jeu 2048 en anglais, Docker Hub).  
Conteneur : **`exercice02-2048`** — accessible sur **http://localhost:8080**

## Commandes exécutées

```bash
# 1. Chercher une image 2048 sur Docker Hub
docker search 2048

# 2. Récupérer l'image localement
docker pull kubespheredev/2048

# 3. Lancer le conteneur (port hôte 8080 → port conteneur 80)
docker run -d --name exercice02-2048 -p 8080:80 kubespheredev/2048
```

## Archive de l'image

Fichier : `docker-2048.tar`

```bash
docker load -i docker-2048.tar
```

## Vérification

```bash
docker ps --filter name=exercice02-2048
curl -I http://localhost:8080
# → HTTP 200
```

Ouvre ensuite dans ton navigateur : **http://localhost:8080**

## Nettoyage (optionnel)

```bash
docker rm -f exercice02-2048
# docker rmi kubespheredev/2048
```
