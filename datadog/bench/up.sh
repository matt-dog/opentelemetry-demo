#!/usr/bin/env bash
# Bring up the DDOT exporter benchmark on the OTel Demo cluster. See BENCHMARK.md.
#
#   bench/up.sh                   demo + tee + three arms, LOCUST_USERS=200
#   LOCUST_USERS=400 bench/up.sh  rerun with a different shop load (idempotent)
#
# Each arm runs three collectors (traces, metrics, logs) on its own node in the
# bench pool, so pod network counters split egress by arm and by signal.
set -euo pipefail
BENCH="$(cd "$(dirname "$0")" && pwd)"
. "$BENCH/../common.sh"

require_bins gcloud kubectl helm
load_env

LOCUST_USERS="${LOCUST_USERS:-200}"
BENCH_MACHINE_TYPE="n2-standard-4"   # n2, not e2: steadier CPU for the CPU numbers
ARMS=(ddot ddotv2 ddototlp)
DDOT_IMAGE="datadog/ddot-collector:7.84.3"
PROFILER="${PROFILER:-1}"            # 0 skips the Full Host Profiler
DATADOG_CHART_VERSION="3.255.0"

# ---- demo with the tee ---------------------------------------------------------
load="$(mktemp)"
trap 'rm -f "$load"' EXIT
cat >"$load" <<EOF
components:
  load-generator:
    envOverrides:
      - name: LOCUST_USERS
        value: "$LOCUST_USERS"
      - name: LOCUST_SPAWN_RATE
        value: "10"
      # Browser users are headless Chromium (1 in 10 by default); ~20 of them
      # OOM the pod at 200 users. HTTP users carry the shop's traffic.
      - name: LOCUST_BROWSER_TRAFFIC_ENABLED
        value: "false"
    # The chart's 1500Mi OOMs at 200 users.
    resources:
      limits:
        memory: 4Gi
# The demo's Prometheus OOMs at its 400Mi under the heavier load. It is not on the
# measured path, but a crash loop adds noise on the default pool.
prometheus:
  server:
    resources:
      limits:
        memory: 1536Mi
EOF
# up.sh only resizes a sleeping cluster, so grow an awake one here first.
# common.sh already defaulted NUM_NODES to 2, so the bench size has its own name.
export NUM_NODES="${BENCH_NUM_NODES:-3}"
if cluster_exists && [ "$(current_nodes)" != "0" ] && [ "$(current_nodes)" -lt "$NUM_NODES" ]; then
  log "Growing $NODE_POOL to $NUM_NODES nodes for the heavier load"
  gc resize "$CLUSTER" --node-pool "$NODE_POOL" --num-nodes "$NUM_NODES" --quiet
fi
EXTRA_VALUES="$BENCH/tee-values.yml,$load" "$DIR/up.sh"

# ---- bench pool ------------------------------------------------------------------
if ! gcloud container node-pools describe "$BENCH_POOL" --cluster "$CLUSTER" \
     --project "$GCP_PROJECT" --zone "$GKE_ZONE" >/dev/null 2>&1; then
  log "Creating $BENCH_POOL (${#ARMS[@]} x $BENCH_MACHINE_TYPE)"
  gcloud container node-pools create "$BENCH_POOL" --cluster "$CLUSTER" \
    --project "$GCP_PROJECT" --zone "$GKE_ZONE" \
    --machine-type "$BENCH_MACHINE_TYPE" --num-nodes "${#ARMS[@]}" \
    --node-taints bench=true:NoSchedule --node-labels bench=true --quiet
else
  log "Sizing $BENCH_POOL to ${#ARMS[@]} nodes"
  gc resize "$CLUSTER" --node-pool "$BENCH_POOL" --num-nodes "${#ARMS[@]}" --quiet
fi

log "Waiting for the bench nodes"
for _ in $(seq 1 60); do
  [ "$(kubectl get nodes -l bench=true --no-headers 2>/dev/null | grep -c ' Ready')" -ge "${#ARMS[@]}" ] && break
  sleep 5
done
nodes=($(kubectl get nodes -l bench=true -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort))
[ "${#nodes[@]}" -ge "${#ARMS[@]}" ] || die "only ${#nodes[@]} bench nodes are Ready"
# Label only nodes without an arm, so growing the pool never moves an arm that
# is already running.
for arm in "${ARMS[@]}"; do
  [ -n "$(kubectl get nodes -l "bench-arm=$arm" -o name)" ] && continue
  free="$(kubectl get nodes -l 'bench=true,!bench-arm' -o name | sort | head -1)"
  [ -n "$free" ] || die "no free bench node for $arm"
  kubectl label "$free" "bench-arm=$arm" >/dev/null
done

# ---- arms ------------------------------------------------------------------------
kubectl -n "$NAMESPACE" create configmap bench-config \
  --from-file="$BENCH/traces.yaml" --from-file="$BENCH/metrics.yaml" --from-file="$BENCH/logs.yaml" \
  --from-file="$BENCH/otlp-traces.yaml" --from-file="$BENCH/otlp-metrics.yaml" --from-file="$BENCH/otlp-logs.yaml" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Every arm runs the same DDOT image with the converter off. ddot and ddotv2 run
# the same config file per signal; ddototlp swaps the exporter (otlp-<signal>.yaml).
arm_conf() {
  case "$1" in
    ddototlp) echo "otlp-$2.yaml" ;;
    *)        echo "$2.yaml" ;;
  esac
}
# Fixed-length host.name suffix per arm, so the arms' env tags stay apart in
# Datadog. Earlier runs used -b1 to -b6; these are new so old host tags don't mix in.
arm_suffix() {
  case "$1" in ddot) echo -b7 ;; ddotv2) echo -b8 ;; ddototlp) echo -b9 ;; esac
}
arm_image() { echo "$DDOT_IMAGE"; }
arm_args() { echo "[\"run\", \"--config\", \"file:/conf/$(arm_conf "$1" "$2")\"]"; }
arm_env() {
  local pad="            "
  # Standalone DDOT asks the core Agent for its hostname and fails without one.
  echo "$pad- {name: DD_HOSTNAME, valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}"
  # The converter would add infraattributes, cumulativetodelta, a self-telemetry
  # scrape and extensions to the config. Off on every arm, so all run what they're given.
  echo "$pad- {name: DD_OTELCOLLECTOR_CONVERTER_FEATURES, value: none}"
  # ddotv2 sends what contrib's Datadog Exporter sends: v2 series with zlib, and gzip logs.
  if [ "$1" = ddotv2 ]; then
    echo "$pad- {name: DD_SERIALIZER_COMPRESSOR_KIND, value: zlib}"
    echo "$pad- {name: DD_USE_V3_API_SERIES_ENABLED, value: \"false\"}"
    echo "$pad- {name: DD_LOGS_CONFIG_COMPRESSION_KIND, value: gzip}"
  fi
  return 0
}

# render_arm <arm> <signal> [idle]. An idle twin runs the same image and config on
# the same node with no input (the tee does not know it), so its egress is the
# arm's fixed traffic outside the measured pipeline: metadata, self-telemetry.
render_arm() {
  local arm="$1" signal="$2" app=bench name="bench-$1-$2"
  if [ "${3:-}" = idle ]; then app=bench-idle; name="bench-idle-$1-$2"; fi
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels: {app: $app, bench-arm: $arm, bench-signal: $signal}
spec:
  replicas: 1
  selector:
    matchLabels: {app: $app, bench-arm: $arm, bench-signal: $signal}
  template:
    metadata:
      labels: {app: $app, bench-arm: $arm, bench-signal: $signal}
      annotations:
        bench/config-hash: "$(shasum <"$BENCH/$(arm_conf "$arm" "$signal")" | cut -c1-12)"
    spec:
      nodeSelector: {bench-arm: $arm}
      tolerations:
        - {key: bench, operator: Exists, effect: NoSchedule}
      containers:
        - name: collector
          image: $(arm_image "$arm")
          args: $(arm_args "$arm" "$signal")
          ports:
            - {name: otlp-grpc, containerPort: 4317}
            - {name: telemetry, containerPort: 8888}
          env:
            - {name: BENCH_ENV, value: bench-$arm$([ $app = bench ] || echo -idle)}
            - {name: BENCH_HOST_SUFFIX, value: "$(arm_suffix "$arm")"}
            - name: DD_API_KEY
              valueFrom: {secretKeyRef: {name: datadog-secret, key: api-key}}
            - name: DD_SITE
              valueFrom: {secretKeyRef: {name: datadog-secret, key: dd-site}}
$(arm_env "$arm")
          resources:
            requests: {cpu: 250m, memory: 256Mi}
            limits: {cpu: "2", memory: 2Gi}
          volumeMounts:
            - {name: config, mountPath: /conf}
      volumes:
        - name: config
          configMap: {name: bench-config}
---
EOF
  [ $app = bench ] || return 0
  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  selector: {app: bench, bench-arm: $arm, bench-signal: $signal}
  ports:
    - {name: otlp-grpc, port: 4317, targetPort: 4317}
    - {name: telemetry, port: 8888, targetPort: 8888}
---
EOF
}

log "Applying the benchmark collectors (${ARMS[*]} x traces, metrics, logs)"
for arm in "${ARMS[@]}"; do
  for signal in traces metrics logs; do
    render_arm "$arm" "$signal"
    render_arm "$arm" "$signal" idle
  done
done | kubectl -n "$NAMESPACE" apply -f - >/dev/null

if [ "$PROFILER" = 1 ]; then
  log "Installing the Full Host Profiler on the bench nodes (datadog chart $DATADOG_CHART_VERSION)"
  helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
  helm repo update datadog >/dev/null
  helm upgrade --install bench-profiler datadog/datadog \
    --version "$DATADOG_CHART_VERSION" --namespace "$NAMESPACE" \
    --values "$BENCH/profiler-values.yml" --set "datadog.site=$DD_SITE" >/dev/null
fi

kubectl -n "$NAMESPACE" rollout status deploy -l 'app in (bench,bench-idle)' --timeout=300s >/dev/null \
  || warn "some benchmark collectors are not ready: kubectl -n $NAMESPACE get pods -l app=bench"

cat <<EOF

Benchmark is up: ${ARMS[*]}, LOCUST_USERS=$LOCUST_USERS, profiler=$PROFILER.
  Profiles:        Datadog Profiling, env:bench-profiler, by pod_name:bench-*
  Check v3 is on:  kubectl -n $NAMESPACE logs deploy/bench-ddot-metrics | grep -i v3
  Snapshot:        python3 -I $BENCH/measure.py start   (then: end, after the run)
  Report:          python3 -I $BENCH/report.py $BENCH/results/<run>
Sleep it afterwards: $DIR/down.sh   (sleeps the bench pool too)
EOF
