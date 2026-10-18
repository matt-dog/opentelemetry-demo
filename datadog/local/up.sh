#!/usr/bin/env bash
# Astronomy Shop collected by the DDOT Collector that the opentelemetry-examples
# kube-stack installer runs (OTel Operator + kube-stack, ddot flow). See README.md.
#
#   datadog/local/up.sh local   Rancher Desktop (context rancher-desktop)
#   datadog/local/up.sh gke     GKE cluster otel-demo-blog, created if missing
#
# Every kubectl and helm call uses a kubeconfig holding only the target cluster,
# so the current context is never used or changed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

TARGET="${1:-local}"
NS=otel-demo
DEMO_CHART_VERSION=0.42.1
DD_SITE="${DD_SITE:-datadoghq.com}"
DD_API_KEY_REF="${DD_API_KEY_REF:-op://Employee/ddot-lab/DD_API_KEY}"
DD_APP_KEY_REF="${DD_APP_KEY_REF:-op://Employee/ddot-lab/DD_APP_KEY}"
KUBE_STACK_DIR="${KUBE_STACK_DIR:-$HOME/code/opentelemetry-examples/guides/kubernetes/configuration/opentelemetry-kube-stack}"
GCP_PROJECT="${GCP_PROJECT:-dd-dev-otelpmdev}"
GKE_ZONE="${GKE_ZONE:-us-east1-b}"
GKE_CLUSTER="${GKE_CLUSTER:-otel-demo-blog}"

kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
chmod 600 "$kubeconfig"
export KUBECONFIG="$kubeconfig"

case "$TARGET" in
  local)
    KUBECONFIG="$HOME/.kube/config" kubectl config view --minify --flatten --context rancher-desktop >"$kubeconfig"
    ENV_NAME=otel-demo-local; CLUSTER_TYPE=other
    HOST_PROFILER="${DD_HOST_PROFILER_ENABLED:-false}" ;;
  gke)
    gc() { gcloud container clusters "$@" --project "$GCP_PROJECT" --zone "$GKE_ZONE"; }
    if ! gc describe "$GKE_CLUSTER" --format='value(name)' >/dev/null 2>&1; then
      echo "Creating GKE cluster $GKE_CLUSTER (5 to 8 minutes)"
      # The project has no "default" network; use the ddot-lab one.
      gc create "$GKE_CLUSTER" --network ddot-lab --subnetwork ddot-lab-us-east1 \
        --enable-ip-alias --machine-type e2-standard-4 --num-nodes 3 \
        --labels purpose=ddot-blog-demo --quiet >/dev/null
    fi
    gc get-credentials "$GKE_CLUSTER" >/dev/null 2>&1   # writes only to $KUBECONFIG
    ENV_NAME=otel-demo-gke-blog; CLUSTER_TYPE=gcp
    # GKE nodes meet the eBPF profiler's needs (kernel >= 5.10, Kubernetes >= 1.30).
    HOST_PROFILER="${DD_HOST_PROFILER_ENABLED:-true}" ;;
  *) echo "usage: up.sh [local|gke]" >&2; exit 2 ;;
esac

# ---- kube-stack: OTel Operator + DDOT collectors, via its own installer ----------
echo "Installing kube-stack (ddot flow, host profiler $HOST_PROFILER) with the shop overlay"
DD_API_KEY="$(op read "$DD_API_KEY_REF")" DD_SITE="$DD_SITE" \
  DD_INSTALL_FLOW=ddot DD_AGENT_ENABLED=false DD_HOST_PROFILER_ENABLED="$HOST_PROFILER" \
  K8S_CLUSTER_NAME="$ENV_NAME" K8S_CLUSTER_TYPE="$CLUSTER_TYPE" \
  DEPLOYMENT_ENVIRONMENT_NAME="$ENV_NAME" \
  "$KUBE_STACK_DIR/install" "$HERE/kube-stack-values.yaml" >/dev/null

# ---- the shop ----------------------------------------------------------------------
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
echo "Installing the Astronomy Shop (chart $DEMO_CHART_VERSION)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version "$DEMO_CHART_VERSION" --namespace "$NS" \
  --values "$HERE/values-local.yaml" >/dev/null

kubectl apply -f "$HERE/shopper.yaml" >/dev/null
kubectl apply -f "$HERE/scenarios.yaml" >/dev/null

echo "Waiting for every pod to be Ready (up to 10 minutes)"
kubectl -n "$NS" wait --for=condition=Ready pods --all --timeout=600s >/dev/null \
  || echo "some pods are not Ready yet: kubectl -n $NS get pods" >&2

# ---- failure scenarios for the blog's error traces --------------------------------
# flagd reads this file live. It resets when the flagd pod restarts; rerun up.sh.
echo "Setting feature flags: paymentFailure 50%, cartFailure 100%, productCatalogFailure on"
flags="$(mktemp)"
kubectl -n "$NS" exec deploy/flagd -c flagd-ui -- cat /app/data/demo.flagd.json >"$flags"
# Edit a copy and write it back whole, so a failure never leaves flagd an empty file.
python3 - "$flags" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); f = d["flags"]
f["paymentFailure"]["defaultVariant"] = "50%"
f["cartFailure"]["defaultVariant"] = "100%"
# The shipped rule returns "off" on both branches, so the flag can never fire.
f["productCatalogFailure"]["targeting"] = {"if": [{"==": [{"var": "product_id"}, "OLJCESPC7Z"]}, "on", "off"]}
json.dump(d, open(sys.argv[1] + ".new", "w"), indent=2)
PY
kubectl -n "$NS" exec -i deploy/flagd -c flagd-ui -- sh -c 'cat > /app/data/demo.flagd.json' <"$flags.new"
rm -f "$flags" "$flags.new"

# ---- Datadog monitors and log index (datadog/, applied by dd-apply.py) ------------
# Skips with a warning when the application key is missing or refused.
DD_API_KEY="$(op read "$DD_API_KEY_REF")" DD_APP_KEY="$(op read "$DD_APP_KEY_REF" 2>/dev/null || true)" \
  DD_SITE="$DD_SITE" ENV_NAME="$ENV_NAME" python3 "$HERE/dd-apply.py" \
  || echo "dd-apply.py failed; the demo is up without its monitors and log index" >&2

cat <<MSG

Astronomy Shop is up ($TARGET), collected by the kube-stack DDOT Collector.
  Datadog:  https://ddstaging.datadoghq.com/apm/traces?query=env%3A$ENV_NAME
MSG
if [ "$TARGET" = gke ]; then
  echo "  kubectl: gcloud container clusters get-credentials $GKE_CLUSTER --project $GCP_PROJECT --zone $GKE_ZONE"
  echo "  then:    kubectl -n $NS port-forward svc/frontend-proxy 8080:8080"
else
  echo "  kubectl --context rancher-desktop -n $NS port-forward svc/frontend-proxy 8080:8080"
fi
echo "  Shop http://localhost:8080  Jaeger /jaeger/ui  Grafana /grafana  Flags /feature"
