# Exercice Docker #9 — API CRUD + API Logs

Deux APIs Spring Boot conteneurisées : CRUD chiens (MySQL) qui envoie ses logs à l'API Logs via **RestTemplate**.

| Service | Conteneur | URL |
|---------|-----------|-----|
| CRUD API | `exercice09-crud-api` | **http://localhost:8084** |
| Logs API | `exercice09-logs-api` | **http://localhost:8085** |
| MySQL | `exercice09-mysql` | localhost:**3309** |

## Démarrage

```bash
cd 03_exercices_rendus/exercice-09
docker compose up -d --build
```

## Endpoints CRUD

| Méthode | URL |
|---------|-----|
| GET | `/api/v1/dogs` |
| GET | `/api/v1/dogs/{dogId}` |
| POST | `/api/v1/dogs` |
| PUT | `/api/v1/dogs/{dogId}` |
| DELETE | `/api/v1/dogs/{dogId}` |

## Endpoints Logs

| Méthode | URL |
|---------|-----|
| GET | `/api/v1/logs` |
| POST | `/api/v1/logs` |

Format d'un log :

```json
{
  "message": "HTTP 200 OK",
  "source": "[CrudAPI] GET /api/v1/dogs",
  "timestamp": "2026-10-09T08:55:44Z",
  "level": "INFO"
}
```

`level` ∈ `INFO` | `WARN` | `ERR`

## Tests

```bash
# CRUD
curl -X POST http://localhost:8084/api/v1/dogs \
  -H "Content-Type: application/json" \
  -d '{"name":"Max","birthDate":"2018-01-20","breed":"Beagle","sterilized":true}'

curl http://localhost:8084/api/v1/dogs

# Provoquer une erreur (log ERR)
curl http://localhost:8084/api/v1/dogs/999

# Consulter les logs générés par le CRUD
curl http://localhost:8085/api/v1/logs
```

## Architecture

```
Navigateur / curl
       │
       ▼
  crud-api (:8084) ──RestTemplate──► logs-api (:8085)
       │
       ▼
     MySQL (:3309)
```

## Arrêt

```bash
docker compose down
```
