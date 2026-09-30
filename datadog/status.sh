#!/usr/bin/env bash
# Is the OTel Demo awake, and where is it? A sleeping demo looks exactly like a
# broken pipeline in Datadog, so check this first.
set -euo pipefail
. "$(dirname "$0")/common.sh"

require_bins gcloud kubectl
load_env

if ! cluster_exists; then
  echo "$CLUSTER: absent (run up.sh)"
  exit 0
fi

nodes="$(current_nodes)"
echo "$CLUSTER: $(gc describe "$CLUSTER" --format='value(status)'), $nodes nodes"
[ "$nodes" = "0" ] && { echo "Asleep. Wake with: $DIR/up.sh"; exit 0; }

use_cluster
ready="$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]==a[2]) r++} END{print r+0 "/" NR}')"
lb="$(kubectl -n "$NAMESPACE" get svc frontend-proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
allowed="$(kubectl -n "$NAMESPACE" get svc frontend-proxy-public -o jsonpath='{.spec.loadBalancerSourceRanges}' 2>/dev/null || true)"
echo "Pods ready: $ready"
echo "Shop:       http://${lb:-<none>}  (allowed: ${allowed:-<none>})"
