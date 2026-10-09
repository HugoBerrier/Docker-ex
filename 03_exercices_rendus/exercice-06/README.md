# Exercice Docker #6 — NGINX + volume de développement

Conteneur utilitaire NGINX qui sert un site codé **sur ton Mac** (sans installer NGINX localement), via un **bind mount** (`-v`).

| Élément | Valeur |
|---------|--------|
| Conteneur | `exercice06-nginx` |
| Image | `nginx:alpine` |
| Dossier local | `site/` |
| URL | **http://localhost:8082** |

## Commande exécutée

```bash
cd 03_exercices_rendus/exercice-06

docker run -d \
  --name exercice06-nginx \
  --restart unless-stopped \
  -p 8082:80 \
  -v "$(pwd)/site":/usr/share/nginx/html:ro \
  nginx:alpine
```

- `-v ...:/usr/share/nginx/html` : le dossier `site/` de l'hôte remplace le contenu web du conteneur
- `:ro` : montage en lecture seule (le conteneur ne modifie pas tes fichiers)

## Utilisation

1. Ouvre **http://localhost:8082**
2. Édite `site/index.html` dans ton éditeur
3. Recharge la page dans le navigateur → les changements apparaissent tout de suite

## Vérification faite

Modification du HTML sur l'hôte immédiatement visible via `curl` (sans rebuild / sans redémarrage du conteneur).

## Nettoyage (optionnel)

```bash
docker rm -f exercice06-nginx
```
