# Exercice Docker #7 — MySQL pré-initialisé (kennelDB)

Image custom MySQL avec script SQL d'init : tables + données dès le premier démarrage.

| Élément | Valeur |
|---------|--------|
| Image | `exercice07-kennel-mysql` |
| Conteneur | `exercice07-mysql` |
| Base | `kennelDB` |
| Root password | `rootpass` |
| Port hôte | **3307** → 3306 |

## Contenu du dossier

- `Dockerfile` — image basée sur `mysql:8.0`
- `init/01-kennelDB.sql` — création DB, tables, inserts
- `exercice07-kennel-mysql.tar` — archive de l'image

## Schéma

| Table | Colonnes |
|-------|----------|
| `clients` | nom, prenom, date_naissance, pseudonyme |
| `adresses` | numero, rue, code_postal, commune |
| `clients_adresses` | association clients ↔ adresses |
| `chiens` | nom, date_naissance, race, sterilise |
| `chats` | nom, date_naissance, race, sterilise |

## Commandes

```bash
cd 03_exercices_rendus/exercice-07

docker build -t exercice07-kennel-mysql .

docker volume create exercice07-mysql-data

docker run -d \
  --name exercice07-mysql \
  --restart unless-stopped \
  -v exercice07-mysql-data:/var/lib/mysql \
  -p 3307:3306 \
  exercice07-kennel-mysql
```

> Le script dans `/docker-entrypoint-initdb.d/` ne s'exécute qu'au **premier** démarrage (volume vide).

## Vérification

```bash
docker exec exercice07-mysql mysql -uroot -prootpass kennelDB -e "SHOW TABLES;"
docker exec exercice07-mysql mysql -uroot -prootpass kennelDB -e "SELECT * FROM clients;"
docker exec exercice07-mysql mysql -uroot -prootpass kennelDB -e "SELECT * FROM chiens;"
docker exec exercice07-mysql mysql -uroot -prootpass kennelDB -e "SELECT * FROM chats;"
```

## Archive

```bash
docker load -i exercice07-kennel-mysql.tar
```

## Nettoyage (optionnel)

```bash
docker rm -f exercice07-mysql
docker volume rm exercice07-mysql-data
# docker rmi exercice07-kennel-mysql
```
