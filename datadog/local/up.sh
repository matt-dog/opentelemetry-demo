#!/usr/bin/env bash
# Astronomy Shop collected by the DDOT Collector that the opentelemetry-examples
# kube-stack installer runs (OTel Operator + kube-stack, ddot flow). See README.md.
#
#   datadog/local/up.sh local   Rancher Desktop (context rancher-desktop)
#   datadog/local/up.sh gke     GKE cluster otel-demo, created if missing
#
# Every kubectl and helm call uses a kubeconfig holding only the target cluster,
# so the current context is never used or changed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

TARGET="${1:-local}"
NS=otel-demo
DEMO_CHART_VERSION=0.42.1
# The matt-dog org on datad0g.com. Set DD_SITE and the two refs to send elsewhere.
DD_SITE="${DD_SITE:-datad0g.com}"
DD_API_KEY_REF="${DD_API_KEY_REF:-op://Employee/ddot-lab/matt-dog-dd-api-key}"
DD_APP_KEY_REF="${DD_APP_KEY_REF:-op://Employee/ddot-lab/matt-dog-dd-app-key}"
ANTHROPIC_API_KEY_REF="${ANTHROPIC_API_KEY_REF:-op://Employee/ddot-lab/ANTHROPIC_API_KEY}"
# The kube-stack installer, copied into kube-stack/ (see kube-stack/README.md).
KUBE_STACK_DIR="${KUBE_STACK_DIR:-$HERE/kube-stack}"
GCP_PROJECT="${GCP_PROJECT:-dd-dev-otelpmdev}"
GKE_ZONE="${GKE_ZONE:-us-east1-b}"
GKE_CLUSTER="${GKE_CLUSTER:-otel-demo}"

kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig" "${kube_stack_values:-}"' EXIT
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
        --labels purpose=otel-demo --quiet >/dev/null
    fi
    gc get-credentials "$GKE_CLUSTER" >/dev/null 2>&1   # writes only to $KUBECONFIG
    ENV_NAME=otel-demo; CLUSTER_TYPE=gcp
    # GKE nodes meet the eBPF profiler's needs (kernel >= 5.10, Kubernetes >= 1.30).
    HOST_PROFILER="${DD_HOST_PROFILER_ENABLED:-true}" ;;
  *) echo "usage: up.sh [local|gke]" >&2; exit 2 ;;
esac

# ---- the API key must belong to DD_SITE; a key from another site is dropped silently --
res="$(curl -s "https://api.$DD_SITE/api/v1/validate" -H "DD-API-KEY: $(op read "$DD_API_KEY_REF")")"
[ "$res" = '{"valid":true}' ] || { echo "DD_API_KEY ($DD_API_KEY_REF) is not valid on $DD_SITE: $res" >&2; exit 1; }

# ---- kube-stack: OTel Operator + DDOT collectors, via its own installer ----------
# The overlay names the env in host tags (__ENV_NAME__); fill it in for this target.
kube_stack_values="$(mktemp)"
sed "s/__ENV_NAME__/$ENV_NAME/g" "$HERE/kube-stack-values.yaml" >"$kube_stack_values"
echo "Installing kube-stack (ddot flow, host profiler $HOST_PROFILER) with the shop overlay"
DD_API_KEY="$(op read "$DD_API_KEY_REF")" DD_SITE="$DD_SITE" \
  DD_INSTALL_FLOW=ddot DD_AGENT_ENABLED=false DD_HOST_PROFILER_ENABLED="$HOST_PROFILER" \
  K8S_CLUSTER_NAME="$ENV_NAME" K8S_CLUSTER_TYPE="$CLUSTER_TYPE" \
  DEPLOYMENT_ENVIRONMENT_NAME="$ENV_NAME" \
  "$KUBE_STACK_DIR/install" "$kube_stack_values" >/dev/null

# ---- Datadog objects from git (datadog/, applied by dd-apply.py) -----------------
# Monitors, the log index and the RUM application. Runs before the shop so the
# rum-config secret (application id and client token) exists when Envoy starts.
# Skips with a warning when the application key is missing or refused.
rum_out="$(mktemp)"; chmod 600 "$rum_out"
DD_API_KEY="$(op read "$DD_API_KEY_REF")" DD_APP_KEY="$(op read "$DD_APP_KEY_REF" 2>/dev/null || true)" \
  DD_SITE="$DD_SITE" ENV_NAME="$ENV_NAME" RUM_OUT="$rum_out" python3 "$HERE/dd-apply.py" \
  || echo "dd-apply.py failed; the demo is up without its monitors, log index and RUM" >&2
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if [ -s "$rum_out" ]; then
  printf "DD_RUM_ENV=%s\nDD_RUM_SITE=%s\n" "$ENV_NAME" "$DD_SITE" >>"$rum_out"
  kubectl -n "$NS" create secret generic rum-config --from-env-file="$rum_out" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi
rm -f "$rum_out"
kubectl -n "$NS" create configmap frontend-proxy-envoy \
  --from-file=envoy.tmpl.yaml="$HERE/frontend-proxy/envoy.tmpl.yaml" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# ---- the shop ----------------------------------------------------------------------
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
echo "Installing the Astronomy Shop (chart $DEMO_CHART_VERSION)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# The load generator's locustfile, with shopping prompts for the agent.
kubectl -n "$NS" create configmap load-generator-locustfile \
  --from-file=locustfile.py="$HERE/load-generator/locustfile.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# The shop's AI agent runs on Claude (values-local.yaml); its key, from 1Password.
kubectl -n "$NS" create secret generic agent-llm \
  --from-literal=ANTHROPIC_API_KEY="$(op read "$ANTHROPIC_API_KEY_REF")" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version "$DEMO_CHART_VERSION" --namespace "$NS" \
  --values "$HERE/values-local.yaml" >/dev/null

kubectl apply -f "$HERE/shopper.yaml" >/dev/null
# The scenarios pod posts a Datadog change event at every flag flip.
kubectl -n "$NS" create configmap scenarios-env --from-literal=DD_ENV="$ENV_NAME" --from-literal=DD_SITE="$DD_SITE" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" create secret generic scenarios-dd --from-literal=DD_API_KEY="$(op read "$DD_API_KEY_REF")" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f "$HERE/scenarios.yaml" >/dev/null

echo "Waiting for every pod to be Ready (up to 10 minutes)"
kubectl -n "$NS" wait --for=condition=Ready pods --all --timeout=600s >/dev/null \
  || echo "some pods are not Ready yet: kubectl -n $NS get pods" >&2

# ---- failure scenarios for error traces -------------------------------------------
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

cat <<MSG

Astronomy Shop is up ($TARGET), collected by the kube-stack DDOT Collector.
  Datadog:  https://app.$DD_SITE/apm/traces?query=env%3A$ENV_NAME
MSG
if [ "$TARGET" = gke ]; then
  echo "  kubectl: gcloud container clusters get-credentials $GKE_CLUSTER --project $GCP_PROJECT --zone $GKE_ZONE"
  echo "  then:    kubectl -n $NS port-forward svc/frontend-proxy 8080:8080"
else
  echo "  kubectl --context rancher-desktop -n $NS port-forward svc/frontend-proxy 8080:8080"
fi
echo "  Shop http://localhost:8080  Jaeger /jaeger/ui  Grafana /grafana  Flags /feature"
