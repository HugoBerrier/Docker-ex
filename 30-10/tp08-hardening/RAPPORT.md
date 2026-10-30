# TP08 — Rapport

## 1. Mesure (`audit.sh`)

Sur la stack TP04 **avant** durcissement : **28 écarts** (transcript `transcripts/audit-avant.txt`).

Principaux : rootfs RW, pas de mémoire / PIDs, pas de `no-new-privileges`, `CapDrop` absent, Traefik avec **socket Docker**, Redis/Traefik en root.

**Après** `compose.hardened.yml` : **0 écart** sur api/worker/db/redis/traefik (`transcripts/audit-apres.txt`).  
Le `socket-proxy` monte encore la socket (attendu) : hors périmètre strict.

### docker-bench-security

Sous Docker Desktop : `DOCKER_API_VERSION=1.44` requis.  
Checks : 105 — **PASS 29 / WARN 284 / INFO 170** (beaucoup de WARN répétés par conteneur/image hors Shop).

**5 WARN prioritaires (daemon / runtime) :**

1. **5.31** — socket Docker montée (dorénavant uniquement dans `socket-proxy`, POST=0)
2. **2.18 / 5.25** — `no-new-privileges` (désormais sur les services Shop)
3. **5.10 / 5.28** — limites mémoire / PIDs
4. **5.12** — rootfs read-only
5. **2.1 / `icc`** — trafic sur bridge défaut (`daemon.json` → `icc: false`)

Score affiché `0` : agrégat bench peu lisible ici ; se fier aux compteurs PASS/WARN.

## 2. Expériences

Voir `EXPERIENCES.md` + `transcripts/experiences.txt`.

## 3. Durcissement

Fichier : `compose.hardened.yml` (commenté).

```bash
cd …/tp04-compose-entreprise
docker run --rm -v shop_redisdata:/data alpine:3.20 chown -R 999:999 /data
docker compose -f compose.yml \
  -f …/tp08-hardening/compose.hardened.yml up -d --wait
./smoke-test.sh   # vert
…/tp08-hardening/audit.sh   # 0 écart
```

Caps Postgres (essai/erreur) : `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`.  
Traefik : `NET_BIND_SERVICE` (écoute :80 en uid 65532).  
Socket Traefik **retirée** → `tecnativa/docker-socket-proxy` sur réseau `shop-socket` **internal**.

Smoke : `transcripts/smoke-hardened.txt` (ready / cache HIT / commande confirmed).

## 4. Daemon

Voir `daemon.json` + `DAEMON.md` (`icc: false`, `live-restore`, `no-new-privileges`, logs rotatifs, `userns-remap` avec effets de bord volumes).
