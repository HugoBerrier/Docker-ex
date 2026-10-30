# Tableau des expériences (étape 2)

| Mesure | Expérience / résultat observé |
|--------|-------------------------------|
| `--read-only` | `touch /x` → `Read-only file system`. Avec `--tmpfs /tmp` : `touch /tmp/x` → OK. |
| `--cap-drop ALL` | Sur Docker Desktop, `ping` a quand même répondu (NET_RAW parfois mal appliqué dans la VM). `chown /tmp` → `Operation not permitted` ; avec `--cap-add CHOWN` → OK. `apk add` a réussi (souvent pas besoin de caps particulières). Sur un Linux Engine, `ping` échoue sans `NET_RAW`. |
| `--security-opt no-new-privileges` | `busybox` / `passwd` (lien setuid) ne peuvent plus élever les privilèges via setuid. |
| `--pids-limit 50` | Boucle de `sleep` en arrière-plan → `can't fork: Resource temporarily unavailable`. |
| `--memory 32m` | `python -c "x='a'*100_000_000"` → `OOMKilled=true`. |
| `--user 1000` | `id` → `uid=1000`. Sur un volume hôte root : écriture souvent refusée (droits). |
| seccomp | `unshare --user` échoue avec le profil défaut (`Operation not permitted`) ; avec `seccomp=unconfined` l'appel passe. Le profil Docker bloque de l'ordre de ~50 syscalls dangereux (namespaces, etc.). |

Transcript brut : `transcripts/experiences.txt`.
