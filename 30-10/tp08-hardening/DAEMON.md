# daemon.json — justifications

Fichier proposé : `daemon.json` (à placer dans `~/.docker/daemon.json` ou `/etc/docker/daemon.json`, puis redémarrer Docker).

| Directive | Effet | Effet de bord |
|-----------|--------|----------------|
| `no-new-privileges: true` | Défaut daemon : aucun conteneur ne peut gagner des privilèges via setuid | Cassera les images qui comptent sur setuid (`passwd`, certains installers) |
| `icc: false` | Coupe la communication inter-conteneurs sur le **bridge par défaut** | Les stacks sans réseau Compose utilisateur ne se parlent plus. **Notre stack Shop** utilise `shop-front` / `shop-back` (réseaux user-defined) : ICC y reste autorisé. Seuls les conteneurs oubliés sur `bridge` sont isolés. |
| `live-restore: true` | Les conteneurs survivent au redémarrage du daemon | Mises à jour Docker plus sûres ; attention aux upgrades majeurs |
| `log-opts` max-size/max-file | Rotation globale des logs json-file | Évite le disque plein (cf. TP07) |
| `userns-remap: default` | Conteneur root ≠ root hôte (UID shift) | **Volumes existants** : les fichiers écrits en root dans le volume deviennent un UID remappé (ex. 165536). Postgres/Redis existants → `permission denied` jusqu'à `chown` / recréation des volumes. Alternative plus douce : **rootless Docker** (pas de remap global, mais ports < 1024 et cAdvisor plus compliqués). |

**Recommandation Shop SAS.** Activer `no-new-privileges`, logs rotatifs, `live-restore`. Garder `icc: false` si toute la prod est sur des réseaux Compose nommés. N'activer `userns-remap` qu'après migration planifiée des volumes (ou stack neuve).
