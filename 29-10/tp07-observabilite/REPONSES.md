# TP07 — Réponses

## Étape 1 — Logs Docker

**Sans `max-size` pendant 6 mois.** Le driver `json-file` grossit sans borne sur le disque de la VM Docker. Disque plein → daemon/apps en panne. La rotation du TP04 (`max-size: 10m`, `max-file: 3`) borne ça.

**Pourquoi stdout/stderr, pas un fichier.** `docker logs`, Promtail et la plupart des collecteurs lisent le driver de logging. Un fichier dans le conteneur disparaît avec le conteneur, n’est pas tourné par Docker, et échappe à la collecte centralisée.

| Driver | Rôle |
|--------|------|
| `json-file` | Défaut, fichier JSON par conteneur, `docker logs` natif |
| `local` | Format compressé interne, meilleure rétention locale |
| `journald` | Envoie au journal systemd de l’hôte |
| `fluentd` / `awslogs` | Envoi distant (Fluentd / CloudWatch) |

**`mode: non-blocking` + `max-buffer-size`.** Si le driver est lent, le conteneur n’attend pas : les logs dépassant le buffer sont **droppés**. Compromis : latence applicative préservée vs perte de logs sous charge.

Preuve TP04 : `docker inspect shop-api-1 --format '{{.HostConfig.LogConfig}}'` → `json-file` + options de rotation.

## Étape 2 — Métriques Docker

- `docker stats` : CPU/MEM live
- `docker system df -v` : images / volumes / build cache
- `docker events` : cycle de vie (start, die, oom)
- `docker inspect --format '{{.State.OOMKilled}}'`

**OOM observé.** `docker update --memory 64m` puis allocation Node jusqu’à OOM :

```text
OOMKilled=true  RestartCount=1
```

Le conteneur est tué puis redémarré (`restart`). Visible aussi via l’alerte `ContainerRestarting` (firing).

## Étape 3 — Stack d’observabilité

Fichiers : `compose.observability.yml`, `prometheus/`, `promtail/`, `loki/`, `grafana/`, `load.sh`.

```bash
# TP04 déjà up (réseaux shop-front / shop-back)
cd tp07-observabilite
docker compose -f compose.observability.yml up -d
./load.sh 1000
open http://localhost:9090/targets
open http://localhost:3001   # admin / admin
```

**Pourquoi pas `docker_sd_configs` dans Prometheus.**  
`docker exec observability-prometheus-1 id` → `uid=65534(nobody)`. Même avec la socket montée, Prometheus ne peut pas parler au daemon. D’où `dns_sd_configs` sur `api` / `worker` (réseaux `shop_front` / `shop_back`).

**cAdvisor** sur Docker Engine 29 : `DOCKER_API_VERSION=1.44` + mount de `docker.sock` (sans monter tout `/var/run`, qui masquait la socket).

**Loki / Promtail.** Collecte via socket, labels `service` / `project` depuis Compose, filtre `project=shop`, extraction JSON `level`.

**Grafana.** Datasources + dashboard `Shop — overview` provisionnés (zéro clic). Port **3001**.

**Alertes** (`prometheus/alerts.yml`) : API down, >5 % 5xx, p95 > 500 ms, redémarrage, mémoire > 90 % limite.

Captures dans `captures/` :

- `prometheus-targets.png`
- `prometheus-alerts.png` (`ShopApiDown` + `ContainerRestarting` **firing**)
- `grafana-dashboard.png`
- `alerts-firing.json`

## Étape 4 — Corrélation (exemple)

Panne injectée : `docker stop shop-api-1`.

1. Grafana / Prometheus : scrape `shop-api` down, alerte `ShopApiDown` firing  
2. Loki : plus de logs `{service="api"}` récents  
3. Vérif : `docker ps -a --filter name=shop-api` → `Exited`

Autre panne déjà vue : limite mémoire 64 Mo → `OOMKilled=true` + `ContainerRestarting`.
