# TP05 — Réponses (avec preuves)

Les transcripts bruts sont dans `transcripts/` (`etape1.txt`, `restore.txt`, `upgrade.txt`, `sidecar.txt`, `seed.txt`).

## Étape 1 — Anatomie du stockage

### Writable layer vs volume

Sur la stack TP04 (`shop_pgdata`) :

```text
docker inspect $(docker compose -f compose.yml ps -q db) --format '{{json .Mounts}}' | jq
→ volume shop_pgdata → /var/lib/postgresql/data
→ bind init.sql → /docker-entrypoint-initdb.d/01-init.sql:ro
→ secret db_password → /run/secrets/db_password
```

`docker volume inspect shop_pgdata` : Mountpoint `/var/lib/docker/volumes/shop_pgdata/_data` (dans la VM Docker Desktop).

Preuve `touch` + `diff` :

```text
docker exec db touch /tmp/x
docker exec db touch /var/lib/postgresql/data/preuve-volume.txt
docker diff <cid>
→ A /tmp/x          # couche writable du conteneur
# le fichier sous /var/lib/postgresql/data n'apparaît PAS dans docker diff
# (écrit dans le volume, pas dans la couche image)
```

Les données Postgres vivent donc dans le **volume nommé**, pas dans la couche writable. Un `docker commit` ou un rebuild d'image ne les sauve pas.

### `down` / `down -v` / `rm` / `volume prune`

Testés sur une **copie** `shopdatademo` (pas la prod) :

| Commande | Conteneurs / réseaux | Volume nommé |
|---|---|---|
| `docker compose down` | supprimés | **conservé** — données encore là au prochain `up` (`SELECT` → 42) |
| `docker compose down -v` | supprimés | **supprimé** — volume ABSENT |
| `docker compose rm` | conteneur enlevé | **conservé** — données encore là (`SELECT` → 7) |
| `docker volume prune` | — | enlève seulement les volumes **dangling** (plus aucun conteneur ne les référence). Un volume encore déclaré dans un compose arrêté mais non `down -v` peut devenir dangling. **Piège** : un prune « pour faire de la place » efface la base. |

### Volume anonyme

```text
docker run -d postgres:16-alpine   # sans -v
→ Docker crée un volume anonyme (hash) monté sur PGDATA
docker rm          → le volume ANONYME reste (dangling)
docker rm -v       → le volume est supprimé avec le conteneur
```

Piège classique : on croit que « sans `-v` il n'y a pas de persistance », or Postgres déclare un VOLUME dans l'image → volume anonyme créé. Au `rm` sans `-v`, les données trainent ; au `rm -v` ou `volume prune`, elles disparaissent sans nom lisible.

### Bind mount vs volume nommé vs `tmpfs`

| Type | Usage | Perf Docker Desktop (macOS/Windows) |
|---|---|---|
| **Volume nommé** | données DB, files Redis, tout ce que le conteneur doit persister sans dépendre du chemin hôte | Stocké dans la VM Linux → I/O proches du natif |
| **Bind mount** | code source, configs, secrets fichiers, init SQL | Traverse le partage FS hôte↔VM → **plus lent**, surtout sur beaucoup de petits fichiers (node_modules) |
| **tmpfs** | caches, `/tmp`, sockets éphémères, `read_only` + écriture temporaire | Mémoire seulement, perdu à l'arrêt — idéal pour secrets volatils / couches read-only |

### Pourquoi `init.sql` n'est pas rejoué

L'entrypoint officiel Postgres n'exécute `/docker-entrypoint-initdb.d/*` **que si le répertoire PGDATA est vide** (premier `initdb`). Dès que `PG_VERSION` existe dans le volume, le script est ignoré.

Forcer une ré-init :

```bash
docker compose down -v          # détruit pgdata
docker compose up -d            # volume vide → init.sql rejoué
# ou : docker volume rm shop_pgdata puis up
```

---

## Étape 2 — Sauvegarde / restauration

Scripts : `backup.sh`, `restore.sh`.

- Dump logique : `pg_dump -Fc` horodaté dans `backups/logical/`
- Dump brut : `alpine` + `tar` sur le volume en `:ro`, après **arrêt** du service (cohérence)
- Rétention : 7 derniers fichiers par type

**Sauvegarde brute incohérente** si Postgres tourne encore : pages à moitié écrites, WAL non flushés. La rendre cohérente : **arrêter** Postgres (choix de `backup.sh`), ou `pg_backup_start` / `pg_backup_stop` (API basenackup / mode archive) pendant le tar, ou un snapshot filesystem atomique.

### Preuve de restauration

Checksum seed : `100000|4be42281faf0c0e116776b41df822db6`

```text
./backup.sh → shop-20261029T110930Z.dump + pgdata-….tar.gz
docker compose -f starter/compose.yml down -v
docker compose -f starter/compose.yml up -d
./restore.sh
checksum après : 100000|4be42281faf0c0e116776b41df822db6
RESTORE_OK
```

Voir `transcripts/restore.txt`.

### Sidecar planifié

`compose.backup.yml` (copie aussi dans le TP04) :

```bash
cd ../tp04-compose-entreprise
docker compose -f compose.yml -f compose.backup.yml up -d pgbackups
```

Image `prodrigestivill/postgres-backup-local:16` (alignée sur Postgres 16), `SCHEDULE: "@every 1m"`. Dumps observés :

```text
backups/scheduled/last/shop-20261029-111724.sql.gz
backups/scheduled/last/shop-20261029-111824.sql.gz
… SQL backup created successfully
```

---

## Étape 3 — Montée de version 14 → 16

Changer simplement le tag `14.13` → `16.4` sur le **même** volume :

```text
FATAL: database files are incompatible with server
DETAIL: The data directory was initialized by PostgreSQL version 14,
        which is not compatible with this version 16.4.
```

Le format on-disk change à chaque majeure. Il faut `pg_upgrade` ou dump/restore.

`upgrade-pg.sh` : checksum avant → `pg_dumpall` + `pg_dump -Fc` → stop PG14 (**volume `shopdata_pgdata` conservé**) → PG16 sur **nouveau** volume `shopdata_pgdata16` → `pg_restore` → checksum après.

```text
avant : 100000|4be42281faf0c0e116776b41df822db6
après : 100000|4be42281faf0c0e116776b41df822db6
OK montée de version 14 → 16
```

`starter/compose.pg16.yml` pointe vers le volume 16. Voir `transcripts/upgrade.txt`.

**Retour arrière** : `docker compose -f starter/compose.pg16.yml down` puis `docker compose -f starter/compose.yml up -d` (volume 14 intact). Ne pas `volume rm shopdata_pgdata`.

| | `pg_dumpall` | `pg_dump` |
|---|---|---|
| Périmètre | cluster entier (roles, tablespaces, toutes les bases) | une base (`shop`) |
| Format | SQL texte | texte, custom `-Fc`, directory |

**Nouveau volume** : PG16 refuse le PGDATA v14 ; garder l'ancien = rollback immédiat.

**Réduire l'indisponibilité** : réplication logique 14→16 puis bascule ; ou `pg_upgrade --link` via `tianon/postgres-upgrade:14-to-16` (hard links, arrêt court, même filesystem).

---

## Étape 4 — Redis

| Mode | Perte max typique |
|---|---|
| `--save 60 1` (RDB) | jusqu'à **60 s** d'écritures (dernier snapshot manqué) |
| `--appendonly yes` (AOF) | selon `appendfsync` : `always` ≈ 0 ; `everysec` (défaut) ≈ **1 s** ; `no` = selon l'OS |

Dans la stack TP04, Redis contient :

1. **Cache** produits (`products`, TTL 30 s) — perte = simple MISS, recalcul depuis Postgres
2. **File** `orders:queue` — perte = commandes déjà en base en `pending` jamais consommées par le worker

Persistance justifiée : **AOF** (`--appendonly yes`, déjà dans le compose TP04) pour ne pas perdre la file. Un RDB seul (`save 60 1`) risque jusqu'à une minute de messages de file. Le cache, lui, n'a pas besoin d'AOF strict : invalidation / TTL suffisent. Compromis retenu : AOF pour la file + volume `redisdata`.
