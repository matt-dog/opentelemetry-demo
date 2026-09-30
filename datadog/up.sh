#!/usr/bin/env bash
# Bring the OTel Demo up: create or wake the GKE cluster, install the demo, the
# cluster collector and kube-state-metrics, open the public URL to ALLOW_CIDRS (default: your
# current public IP). Safe to rerun; every step is idempotent.
#
# Run it from the network you will present on: the public URL only admits the IP
# this script sees.
set -euo pipefail
. "$(dirname "$0")/common.sh"

require_bins gcloud kubectl helm curl
load_env
resolve_api_key

# ---- cluster ---------------------------------------------------------------
if ! cluster_exists; then
  log "Creating GKE cluster $CLUSTER (${NUM_NODES} x ${MACHINE_TYPE}), 5 to 8 minutes"
  gc create "$CLUSTER" \
    --num-nodes "$NUM_NODES" \
    --machine-type "$MACHINE_TYPE" \
    --release-channel regular \
    --enable-ip-alias \
    --network ddot-lab \
    --subnetwork ddot-lab-us-east1 \
    --cluster-secondary-range-name pods \
    --services-secondary-range-name services \
    --workload-pool "${GCP_PROJECT}.svc.id.goog" \
    --labels "lab=ddot-lab,profile=otel-demo"
elif [ "$(current_nodes)" = "0" ]; then
  log "Waking $CLUSTER: scaling $NODE_POOL to $NUM_NODES nodes"
  gc resize "$CLUSTER" --node-pool "$NODE_POOL" --num-nodes "$NUM_NODES" --quiet
else
  log "$CLUSTER is already awake ($(current_nodes) nodes)"
fi
use_cluster

# ---- secrets ---------------------------------------------------------------
# dd-secrets: names from the OTel Demo guide. datadog-secret: names from the
# Kubernetes Explorer guide.
log "Applying namespace and secrets"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NAMESPACE" create secret generic dd-secrets \
  --from-literal="DD_SITE_PARAMETER=$DD_SITE" \
  --from-literal="DD_API_KEY=$DD_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NAMESPACE" create secret generic datadog-secret \
  --from-literal="api-key=$DD_API_KEY" \
  --from-literal="dd-site=$DD_SITE" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ---- charts ----------------------------------------------------------------
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry prometheus-community >/dev/null

log "Installing the OTel Demo (chart $DEMO_CHART_VERSION)"
helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version "$DEMO_CHART_VERSION" --namespace "$NAMESPACE" \
  --values "$DIR/my-values-file.yml" >/dev/null

# kube-state-metrics feeds the Kubernetes dashboards through the cluster collector.
log "Installing kube-state-metrics (chart $KSM_CHART_VERSION)"
helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
  --version "$KSM_CHART_VERSION" --namespace "$NAMESPACE" >/dev/null

# Earlier versions of this demo ran an Explorer-only collector; the cluster
# collector replaces it.
if helm -n "$NAMESPACE" status k8s-explorer >/dev/null 2>&1; then
  log "Removing the old k8s-explorer collector"
  helm -n "$NAMESPACE" uninstall k8s-explorer >/dev/null
fi

log "Installing the cluster collector (chart $COLLECTOR_CHART_VERSION)"
helm upgrade --install otel-cluster-collector open-telemetry/opentelemetry-collector \
  --version "$COLLECTOR_CHART_VERSION" --namespace "$NAMESPACE" \
  --values "$DIR/cluster-collector.yaml" >/dev/null

# ---- public URL ------------------------------------------------------------
cidrs="${ALLOW_CIDRS:-}"
if [ -z "$cidrs" ]; then
  cidrs="$(curl -s https://api.ipify.org)/32"
fi
yaml_cidrs="$(printf '"%s",' ${cidrs//,/ })"
log "Opening the public URL to: $cidrs"
sed "s|ALLOW_CIDRS|${yaml_cidrs%,}|" "$DIR/frontend-lb.yaml" | kubectl apply -f - >/dev/null

# ---- wait ------------------------------------------------------------------
log "Waiting for every pod to be Ready (up to 10 minutes)"
kubectl -n "$NAMESPACE" wait --for=condition=Ready pods --all --timeout=600s >/dev/null \
  || warn "some pods are not Ready yet: kubectl -n $NAMESPACE get pods"

lb=""
for _ in $(seq 1 60); do
  lb="$(kubectl -n "$NAMESPACE" get svc frontend-proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [ -n "$lb" ] && break
  sleep 5
done
[ -n "$lb" ] || die "LoadBalancer has no external IP yet: kubectl -n $NAMESPACE get svc frontend-proxy-public"

# The flag UI writes to an emptyDir, so toggles survive until the flagd pod
# restarts (a wake resets them; a rerun on an awake cluster does not). List any
# that are still on so nothing surprises you mid-demo.
on_flags="$(kubectl -n "$NAMESPACE" exec deploy/flagd -c flagd-ui -- cat /app/data/demo.flagd.json 2>/dev/null | python3 -c '
import sys, json
for name, f in json.load(sys.stdin)["flags"].items():
    if f.get("defaultVariant") != "off": print(name)
' || echo "(could not read flag state)")"
[ -z "$on_flags" ] || warn "flags on, turn them off at /feature: $(echo $on_flags)"

cat <<EOF

OTel Demo is up.
  Shop:        http://$lb
  Flags:       http://$lb/feature
  Datadog:     https://ddstaging.datadoghq.com  (env:$DD_ENV, cluster $DD_CLUSTER_NAME)
Give Datadog 15 to 30 minutes of traffic before presenting.
Sleep it afterwards: $DIR/down.sh
EOF
