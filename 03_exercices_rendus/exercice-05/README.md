# Exercice Docker #5 — MySQL et Adminer

| Élément | Valeur |
|---------|--------|
| Réseau | `exercice05-net` |
| Volume | `exercice05-mysql-data` |
| MySQL | `exercice05-mysql` (non exposé sur l'hôte) |
| Adminer | `exercice05-adminer` → **http://localhost:8081** |

> Port **8081** car le 8080 est déjà pris par l'exercice 03.

## Identifiants Adminer

| Champ | Valeur |
|-------|--------|
| Système | MySQL |
| Serveur | `exercice05-mysql` |
| Utilisateur | `exo05` |
| Mot de passe | `exo05pass` |
| Base de données | `exercice05` |

## Commandes exécutées (sans Compose)

```bash
docker network create exercice05-net
docker volume create exercice05-mysql-data

docker run -d \
  --name exercice05-mysql \
  --network exercice05-net \
  --restart unless-stopped \
  -v exercice05-mysql-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=rootpass \
  -e MYSQL_DATABASE=exercice05 \
  -e MYSQL_USER=exo05 \
  -e MYSQL_PASSWORD=exo05pass \
  mysql:8.0

docker run -d \
  --name exercice05-adminer \
  --network exercice05-net \
  --restart unless-stopped \
  -p 8081:8080 \
  adminer
```

Table créée + 3 enregistrements dans `etudiants` (Dupont, Martin, Bernard).

## Bonus — Compose

```bash
# Si les conteneurs manuels tournent déjà, les arrêter d'abord :
# docker rm -f exercice05-mysql exercice05-adminer

cd 03_exercices_rendus/exercice-05
docker compose up -d
```

## Vérifications faites

- Communication par **nom** (`exercice05-mysql`), pas d'IP fixe
- Volume : données présentes après `docker rm` + recreation du conteneur MySQL
- `--restart unless-stopped` : redémarrage après crash du process
- Seul Adminer publié sur l'hôte (`8081→8080`)

## À faire de ton côté

1. Ouvre **http://localhost:8081**
2. Connecte-toi avec les identifiants ci-dessus (serveur = `exercice05-mysql`)
3. Ouvre la table `etudiants` et vérifie les 3 lignes

## Nettoyage (optionnel)

```bash
docker rm -f exercice05-mysql exercice05-adminer
docker network rm exercice05-net
# docker volume rm exercice05-mysql-data   # efface aussi les données
```
