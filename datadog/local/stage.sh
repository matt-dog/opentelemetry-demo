#!/usr/bin/env bash
# Start and stop the demo's problem on cue, for a live presentation (DEMO-SCRIPT.md).
#
#   datadog/local/stage.sh start [gke|local]   pause the schedule, turn adHighCpu on
#   datadog/local/stage.sh stop  [gke|local]   turn it off, hand back to the schedule
#   datadog/local/stage.sh status [gke|local]  the flag, and whether the schedule runs
#
# The scenarios pod (scenarios.yaml) holds adHighCpu to :30 to :45 each hour and
# would undo a flip within 30 s, so start scales it to 0 and stop scales it back.
# Each flip posts the same Datadog change event the pod posts, so the monitor and
# the service page show "adHighCpu on (ad)". Start it 5 to 10 minutes before Act 1:
# p95 rises within a minute and the latency monitor alerts after its 5-minute window.
# Like up.sh, every kubectl call uses a kubeconfig holding only the target cluster.
set -euo pipefail

ACTION="${1:-status}"
TARGET="${2:-gke}"
NS=otel-demo
GCP_PROJECT="${GCP_PROJECT:-dd-dev-otelpmdev}"
GKE_ZONE="${GKE_ZONE:-us-east1-b}"
GKE_CLUSTER="${GKE_CLUSTER:-otel-demo}"
FLAG=adHighCpu
SERVICE=ad

kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
chmod 600 "$kubeconfig"
export KUBECONFIG="$kubeconfig"
case "$TARGET" in
  gke) gcloud container clusters get-credentials "$GKE_CLUSTER" --project "$GCP_PROJECT" --zone "$GKE_ZONE" >/dev/null 2>&1 ;;
  local) KUBECONFIG="$HOME/.kube/config" kubectl config view --minify --flatten --context rancher-desktop >"$kubeconfig" ;;
  *) echo "usage: stage.sh start|stop|status [gke|local]" >&2; exit 2 ;;
esac

flag_file=/app/data/demo.flagd.json
current() {
  kubectl -n "$NS" exec deploy/flagd -c flagd-ui -- cat "$flag_file" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['flags']['$FLAG']['defaultVariant'])"
}

# Edit a copy and write it back whole, so a failure never leaves flagd an empty file.
set_flag() {
  local variant="$1" tmp
  tmp="$(mktemp)"
  kubectl -n "$NS" exec deploy/flagd -c flagd-ui -- cat "$flag_file" >"$tmp"
  python3 - "$tmp" "$FLAG" "$variant" <<'PY'
import json, sys
path, flag, variant = sys.argv[1:]
d = json.load(open(path))
d["flags"][flag]["defaultVariant"] = variant
json.dump(d, open(path + ".new", "w"), indent=2)
PY
  kubectl -n "$NS" exec -i deploy/flagd -c flagd-ui -- sh -c "cat > $flag_file" <"$tmp.new"
  rm -f "$tmp" "$tmp.new"
}

# The change event, as scenarios.yaml posts it. Key and site from the cluster.
change_event() {
  local old="$1" new="$2" key site env
  key="$(kubectl -n "$NS" get secret scenarios-dd -o jsonpath='{.data.DD_API_KEY}' | base64 -d)"
  site="$(kubectl -n "$NS" get configmap scenarios-env -o jsonpath='{.data.DD_SITE}')"
  env="$(kubectl -n "$NS" get configmap scenarios-env -o jsonpath='{.data.DD_ENV}')"
  python3 - "$old" "$new" "$env" <<PY | curl -s -o /dev/null -w "change event: %{http_code}\n" \
      -X POST "https://event-management-intake.$site/api/v2/events" \
      -H "Content-Type: application/json" -H "DD-API-KEY: $key" --data-binary @-
import json, sys
old, new, env = sys.argv[1:]
print(json.dumps({"data": {"type": "event", "attributes": {
    "category": "change", "integration_id": "custom-events",
    "title": f"$FLAG {new} ($SERVICE)",
    "message": f"Stage cue set feature flag $FLAG from {old} to {new}.",
    "tags": [f"env:{env}", "service:$SERVICE", "source:stage"],
    "attributes": {
        "changed_resource": {"name": "$FLAG", "type": "feature_flag"},
        "impacted_resources": [{"name": "$SERVICE", "type": "service"}],
        "prev_value": {"variant": old}, "new_value": {"variant": new},
        "author": {"name": "stage.sh", "type": "automation"}}}}}))
PY
}

schedule() { kubectl -n "$NS" get deploy scenarios -o jsonpath='{.spec.replicas}'; }

case "$ACTION" in
  start)
    kubectl -n "$NS" scale deploy/scenarios --replicas=0 >/dev/null
    kubectl -n "$NS" wait --for=delete pod -l app=scenarios --timeout=60s >/dev/null 2>&1 || true
    old="$(current)"
    set_flag on
    change_event "$old" on
    echo "$FLAG on, schedule paused. Act 1 is ready in about 5 minutes (monitor window)." ;;
  stop)
    old="$(current)"
    set_flag off
    change_event "$old" off
    kubectl -n "$NS" scale deploy/scenarios --replicas=1 >/dev/null
    echo "$FLAG off, schedule back (it turns $FLAG on again from :30 to :45 each hour, UTC)." ;;
  status)
    echo "$FLAG: $(current); schedule replicas: $(schedule)" ;;
  *) echo "usage: stage.sh start|stop|status [gke|local]" >&2; exit 2 ;;
esac
