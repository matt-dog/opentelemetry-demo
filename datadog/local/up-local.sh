#!/usr/bin/env bash
# Astronomy Shop on Rancher Desktop, collected by the DDOT Collector that the
# opentelemetry-examples kube-stack installer runs (OTel Operator + kube-stack,
# ddot flow). See README.md.
#
#   datadog/local/up-local.sh
#
# Every kubectl and helm call names the context (or uses a kubeconfig holding only
# that context), so the current context, often a GKE cluster, is never used or
# changed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

CTX="${KUBE_CONTEXT:-rancher-desktop}"
NS=otel-demo
DEMO_CHART_VERSION=0.42.1
DD_SITE="${DD_SITE:-datadoghq.com}"
DD_API_KEY_REF="${DD_API_KEY_REF:-op://Employee/ddot-lab/DD_API_KEY}"
KUBE_STACK_DIR="${KUBE_STACK_DIR:-$HOME/code/opentelemetry-examples/guides/kubernetes/configuration/opentelemetry-kube-stack}"

k() { kubectl --context "$CTX" "$@"; }

# ---- kube-stack: OTel Operator + DDOT collectors, via its own installer ----------
# The installer acts on the current context, so it gets a kubeconfig with only CTX.
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
chmod 600 "$kubeconfig"
kubectl config view --minify --flatten --context "$CTX" >"$kubeconfig"
echo "Installing kube-stack (ddot flow) with the shop overlay"
KUBECONFIG="$kubeconfig" \
  DD_API_KEY="$(op read "$DD_API_KEY_REF")" DD_SITE="$DD_SITE" \
  DD_INSTALL_FLOW=ddot DD_AGENT_ENABLED=false \
  K8S_CLUSTER_NAME=otel-demo-local K8S_CLUSTER_TYPE=other \
  DEPLOYMENT_ENVIRONMENT_NAME=otel-demo-local \
  "$KUBE_STACK_DIR/install" "$HERE/kube-stack-values.yaml" >/dev/null

# ---- the shop ----------------------------------------------------------------------
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null
echo "Installing the Astronomy Shop (chart $DEMO_CHART_VERSION)"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
helm --kube-context "$CTX" upgrade --install my-otel-demo open-telemetry/opentelemetry-demo \
  --version "$DEMO_CHART_VERSION" --namespace "$NS" \
  --values "$HERE/values-local.yaml" >/dev/null

echo "Waiting for every pod to be Ready (up to 10 minutes)"
k -n "$NS" wait --for=condition=Ready pods --all --timeout=600s >/dev/null \
  || echo "some pods are not Ready yet: kubectl --context $CTX -n $NS get pods" >&2

cat <<EOF

Astronomy Shop is up on $CTX, collected by the kube-stack DDOT Collector.
  kubectl --context $CTX -n $NS port-forward svc/frontend-proxy 8080:8080
  Shop:     http://localhost:8080
  Jaeger:   http://localhost:8080/jaeger/ui
  Grafana:  http://localhost:8080/grafana
  Flags:    http://localhost:8080/feature
  Datadog:  https://ddstaging.datadoghq.com/apm/traces?query=env%3Aotel-demo-local
EOF
