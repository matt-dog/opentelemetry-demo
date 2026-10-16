#!/usr/bin/env bash
# Unattended run after bench/up.sh: warmup, then REPEATS windows of WINDOW_MIN
# minutes with a snapshot at the midpoint, rotating arms across nodes between
# windows. See BENCHMARK.md.
#
#   bench/campaign.sh <name>     results in bench/results/<name>-r1, -r2, ...
set -euo pipefail
BENCH="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:?usage: campaign.sh <name>}"
REPEATS="${REPEATS:-3}"
WINDOW_MIN="${WINDOW_MIN:-90}"
WARMUP_MIN="${WARMUP_MIN:-30}"
REWARM_MIN="${REWARM_MIN:-15}"
NS=otel-demo
VER="$BENCH/results/$NAME-verification"
mkdir -p "$VER"

say() { echo "$(date '+%F %T') $*"; }
# The laptop's network drops now and then; ride it out instead of losing the run.
retry() {
  local i
  for i in 1 2 3 4 5 6; do "$@" && return 0; say "retry $i: $*"; sleep 30; done
  return 1
}

# Logs compression on the DDOT arms was never checked at runtime. Debug logging
# restarts the pods, so do it first and let the warmup absorb it.
verify() {
  for arm in ddot ddotv2; do
    for sig in metrics logs; do
      kubectl -n "$NS" set env "deploy/bench-$arm-$sig" DD_LOG_LEVEL=debug >/dev/null
    done
  done
  kubectl -n "$NS" rollout status deploy -l app=bench --timeout=300s >/dev/null
  sleep 240
  for arm in ddot ddotv2; do
    for sig in metrics logs; do
      kubectl -n "$NS" logs "deploy/bench-$arm-$sig" --tail=-1 \
        | grep -iE 'compress|zstd|gzip|zlib|v3/series|v2/series|infraattributes|prometheus' \
        | sed -E 's/(api_key|DD-API-KEY|key)[=: ]+[A-Za-z0-9*]+/\1=<redacted>/gi' \
        | head -200 >"$VER/$arm-$sig.log" || true
      kubectl -n "$NS" set env "deploy/bench-$arm-$sig" DD_LOG_LEVEL- >/dev/null
    done
  done
  kubectl -n "$NS" rollout status deploy -l app=bench --timeout=300s >/dev/null
}
say "verification: debug logs on DDOT metrics and logs pods"
verify || say "verification failed; continuing"
for d in $(kubectl -n "$NS" get deploy -l app=bench -o name 2>/dev/null); do
  kubectl -n "$NS" set env "$d" DD_LOG_LEVEL- >/dev/null 2>&1 || true
done

say "warmup ${WARMUP_MIN}m"
sleep $((WARMUP_MIN * 60))

half=$((WINDOW_MIN * 30))
for r in $(seq 1 "$REPEATS"); do
  run="$NAME-r$r"
  kubectl get nodes -l bench=true -L bench-arm --no-headers | awk '{print $1, $NF}' \
    >"$BENCH/results/$run.nodes" 2>/dev/null || true
  say "$run start"
  retry python3 -I "$BENCH/measure.py" "$run" start
  sleep "$half"
  retry python3 -I "$BENCH/measure.py" "$run" mid
  sleep "$half"
  retry python3 -I "$BENCH/measure.py" "$run" end
  python3 -I "$BENCH/report.py" "$BENCH/results/$run" >/dev/null
  python3 -I "$BENCH/report.py" "$BENCH/results/$run" --from start --to mid >/dev/null
  python3 -I "$BENCH/report.py" "$BENCH/results/$run" --from mid --to end >/dev/null
  say "$run done"
  if [ "$r" -lt "$REPEATS" ]; then
    say "rotating arms"
    retry "$BENCH/rotate.sh"
    sleep $((REWARM_MIN * 60))
  fi
done
say "campaign done"
