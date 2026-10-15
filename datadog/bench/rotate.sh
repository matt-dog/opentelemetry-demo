#!/usr/bin/env bash
# Move every arm to the next bench node and restart its pods, so node-to-node
# differences average out over repeats. See BENCHMARK.md.
set -euo pipefail
NS=otel-demo
nodes=($(kubectl get nodes -l bench=true -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort))
arms=()
for n in "${nodes[@]}"; do
  arms+=("$(kubectl get node "$n" -o jsonpath='{.metadata.labels.bench-arm}')")
done
count=${#nodes[@]}
for i in "${!nodes[@]}"; do
  arm="${arms[$(( (i + count - 1) % count ))]}"
  [ -n "$arm" ] && kubectl label node "${nodes[$i]}" "bench-arm=$arm" --overwrite >/dev/null
done
kubectl -n "$NS" rollout restart deploy -l 'app in (bench,bench-idle)' >/dev/null
kubectl -n "$NS" rollout status deploy -l 'app in (bench,bench-idle)' --timeout=300s >/dev/null
for n in "${nodes[@]}"; do
  echo "$n $(kubectl get node "$n" -o jsonpath='{.metadata.labels.bench-arm}')"
done
