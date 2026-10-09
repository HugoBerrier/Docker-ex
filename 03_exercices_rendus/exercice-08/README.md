# Exercice Docker #8 — API Spring Boot + MySQL

API Java (Spring Boot + Hibernate/JPA) pour un CRUD sur l'entité **Dog**, connectée à MySQL conteneurisé.

| Service | Conteneur | Accès |
|---------|-----------|-------|
| API | `exercice08-api` | **http://localhost:8083** |
| MySQL | `exercice08-mysql` | localhost:**3308** |

## Endpoints

| Méthode | URL | Description |
|---------|-----|-------------|
| GET | `/api/v1/dogs` | Liste des chiens |
| GET | `/api/v1/dogs/{dogId}` | Détail d'un chien |
| POST | `/api/v1/dogs` | Création |
| PUT | `/api/v1/dogs/{dogId}` | Modification |
| DELETE | `/api/v1/dogs/{dogId}` | Suppression |

## Contenu

- `api/` — projet Spring Boot + `Dockerfile`
- `compose.yaml` — MySQL + API sur le réseau `exercice08-net`

## Démarrage

```bash
cd 03_exercices_rendus/exercice-08
docker compose up -d --build
```

## Exemples de test

```bash
# Liste
curl http://localhost:8083/api/v1/dogs

# Création
curl -X POST http://localhost:8083/api/v1/dogs \
  -H "Content-Type: application/json" \
  -d '{"name":"Rex","birthDate":"2019-04-01","breed":"Berger Allemand","sterilized":true}'

# Détail
curl http://localhost:8083/api/v1/dogs/1

# Modification
curl -X PUT http://localhost:8083/api/v1/dogs/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Rex Junior","birthDate":"2019-04-01","breed":"Berger Allemand","sterilized":true}'

# Suppression
curl -X DELETE http://localhost:8083/api/v1/dogs/1
```

## Identifiants MySQL

| Champ | Valeur |
|-------|--------|
| Host (hôte) | `localhost:3308` |
| Host (depuis l'API Docker) | `exercice08-mysql:3306` |
| Database | `dogsdb` |
| User | `dogs` |
| Password | `dogspass` |

## Arrêt

```bash
docker compose down
# docker compose down -v   # + suppression des données MySQL
```
