#!/usr/bin/env bash
# Audit CIS-light des conteneurs d'un projet Compose (défaut : shop).
# Affiche utilisateur, Privileged, capabilities, rootfs RO, Memory, PidsLimit,
# no-new-privileges, montage de la socket Docker. Exit ≠ 0 s'il reste des écarts.
set -euo pipefail

PROJECT="${COMPOSE_PROJECT:-shop}"
STRICT_SERVICES="${STRICT_SERVICES:-api,worker,db,redis,traefik}"

echo "=== audit projet=${PROJECT} ==="
echo

gaps=0
found=0

ids=$(docker ps -q --filter "label=com.docker.compose.project=${PROJECT}" 2>/dev/null || true)
if [ -z "$ids" ]; then
  echo "aucun conteneur pour le projet ${PROJECT}" >&2
  exit 2
fi

is_strict() {
  local svc=$1
  case ",${STRICT_SERVICES}," in
    *",${svc},"*) return 0 ;;
    *) return 1 ;;
  esac
}

for id in $ids; do
  found=$((found + 1))
  name=$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')
  svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id")
  user=$(docker inspect -f '{{.Config.User}}' "$id")
  [ -z "$user" ] && user="(image default / root)"
  real_pid=$(docker inspect -f '{{.State.Pid}}' "$id")
  if [ "${real_pid:-0}" != "0" ] && [ -r "/proc/${real_pid}/status" ]; then
    uid_line=$(awk '/^Uid:/{print $2}' "/proc/${real_pid}/status" 2>/dev/null || echo "?")
  else
    uid_line=$(docker exec "$id" id -u 2>/dev/null || echo "?")
  fi
  privileged=$(docker inspect -f '{{.HostConfig.Privileged}}' "$id")
  cap_add=$(docker inspect -f '{{json .HostConfig.CapAdd}}' "$id")
  cap_drop=$(docker inspect -f '{{json .HostConfig.CapDrop}}' "$id")
  readonly_rootfs=$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$id")
  memory=$(docker inspect -f '{{.HostConfig.Memory}}' "$id")
  pids=$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$id")
  security=$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$id")
  mounts=$(docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' "$id")

  sock=no
  if printf '%s' "$mounts" | grep -q 'docker.sock'; then
    sock=yes
  fi

  nnp=no
  if printf '%s' "$security" | grep -qi 'no-new-privileges'; then
    nnp=yes
  fi

  mem_h=unlimited
  if [ "${memory:-0}" != "0" ] && [ "${memory:-0}" != "<nil>" ]; then
    mem_h="${memory}"
  fi
  pids_h=unlimited
  if [ -n "${pids}" ] && [ "${pids}" != "0" ] && [ "${pids}" != "<nil>" ]; then
    pids_h="${pids}"
  fi

  echo "--- ${name} (service=${svc}) ---"
  echo "  User(config)=${user}  Pid1UID=${uid_line}"
  echo "  Privileged=${privileged}"
  echo "  CapAdd=${cap_add}"
  echo "  CapDrop=${cap_drop}"
  echo "  ReadonlyRootfs=${readonly_rootfs}"
  echo "  Memory=${mem_h}  PidsLimit=${pids_h}"
  echo "  no-new-privileges=${nnp}"
  echo "  docker.sock=${sock}"

  if ! is_strict "$svc"; then
    echo "  (hors périmètre strict)"
    echo
    continue
  fi

  if [ "$privileged" = "true" ]; then
    echo "  ECART: Privileged=true"
    gaps=$((gaps + 1))
  fi
  if [ "$sock" = "yes" ]; then
    echo "  ECART: socket Docker montée"
    gaps=$((gaps + 1))
  fi
  if [ "$readonly_rootfs" != "true" ]; then
    echo "  ECART: rootfs non read-only"
    gaps=$((gaps + 1))
  fi
  if [ "$mem_h" = "unlimited" ]; then
    echo "  ECART: pas de limite mémoire"
    gaps=$((gaps + 1))
  fi
  if [ "$pids_h" = "unlimited" ]; then
    echo "  ECART: pas de PidsLimit"
    gaps=$((gaps + 1))
  fi
  if [ "$nnp" != "yes" ]; then
    echo "  ECART: no-new-privileges absent"
    gaps=$((gaps + 1))
  fi
  if ! printf '%s' "$cap_drop" | grep -q 'ALL'; then
    echo "  ECART: CapDrop ne contient pas ALL"
    gaps=$((gaps + 1))
  fi
  if [ "$svc" != "db" ]; then
    cfg_user=$(docker inspect -f '{{.Config.User}}' "$id")
    if [ -z "$cfg_user" ] || [ "$cfg_user" = "0" ] || [ "$cfg_user" = "root" ]; then
      if [ "$uid_line" = "0" ]; then
        echo "  ECART: processus root (uid 0)"
        gaps=$((gaps + 1))
      fi
    fi
  fi
  echo
done

echo "=== résumé : ${found} conteneur(s), ${gaps} écart(s) ==="
if [ "$gaps" -gt 0 ]; then
  exit 1
fi
exit 0
