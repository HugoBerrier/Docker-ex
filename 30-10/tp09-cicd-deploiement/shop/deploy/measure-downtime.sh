#!/usr/bin/env bash
# Mesure les échecs HTTP pendant un déploiement (cible ~100 req/s sur /health).
# Usage: ./deploy/measure-downtime.sh [durée_secondes]
# Env: BASE_URL (défaut http://127.0.0.1), HOST_HEADER (défaut api.localhost)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DURATION="${1:-30}"
BASE_URL="${BASE_URL:-http://127.0.0.1}"
HOST_HEADER="${HOST_HEADER:-api.localhost}"
URL="${BASE_URL%/}/health"
CONCURRENCY="${CONCURRENCY:-20}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${ROOT}/transcripts/downtime-${STAMP}.txt"
mkdir -p "${ROOT}/transcripts"

echo "== mesure downtime : ${URL} Host=${HOST_HEADER} pendant ${DURATION}s (~100 req/s) =="
echo "log: ${OUT}"

python3 - "$URL" "$DURATION" "$CONCURRENCY" "$OUT" "$HOST_HEADER" <<'PY'
import sys, time, urllib.request, urllib.error, threading

url, duration, concurrency, out_path, host = (
    sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
)
stop_at = time.time() + duration
ok = fail = 0
lock = threading.Lock()
errors = []

def worker():
    global ok, fail
    while time.time() < stop_at:
        t0 = time.time()
        try:
            req = urllib.request.Request(url, headers={"Host": host})
            with urllib.request.urlopen(req, timeout=2) as r:
                code = r.getcode()
                r.read(64)
            if 200 <= code < 300:
                with lock:
                    ok += 1
            else:
                with lock:
                    fail += 1
                    errors.append(f"{time.time():.3f} HTTP {code}")
        except Exception as e:
            with lock:
                fail += 1
                errors.append(f"{time.time():.3f} {type(e).__name__}: {e}")
        elapsed = time.time() - t0
        # 20 workers × ~5 Hz ≈ 100 req/s
        time.sleep(max(0.0, 0.18 - elapsed))

threads = [threading.Thread(target=worker, daemon=True) for _ in range(concurrency)]
for t in threads:
    t.start()
for t in threads:
    t.join()

total = ok + fail
rate = total / duration if duration else 0
summary = (
    f"url={url}\n"
    f"host={host}\n"
    f"duration_s={duration}\n"
    f"concurrency={concurrency}\n"
    f"ok={ok}\n"
    f"fail={fail}\n"
    f"total={total}\n"
    f"req_per_s={rate:.1f}\n"
    f"error_samples:\n" + "\n".join(errors[:40]) + ("\n..." if len(errors) > 40 else "")
)
open(out_path, "w").write(summary + "\n")
print(summary)
print(f"FAIL_COUNT={fail}")
sys.exit(0 if fail == 0 else 1)
PY
