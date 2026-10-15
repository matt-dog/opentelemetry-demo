#!/usr/bin/env bash
# Bring up the DDOT vs contrib benchmark on the OTel Demo cluster. See BENCHMARK.md.
#
#   bench/up.sh                   demo + tee + four arms, LOCUST_USERS=200
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
ARMS=(contrib contribotlp ddot ddotv2 ddotdefault contribotlpeq)
CONTRIB_IMAGE="otel/opentelemetry-collector-contrib:0.159.0"   # the upstream version DDOT 7.84.3 embeds
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
  --from-file="$BENCH/otlpeq-traces.yaml" --from-file="$BENCH/otlpeq-metrics.yaml" --from-file="$BENCH/otlpeq-logs.yaml" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Every arm gets the same config, resources and node shape. Only the image, its
# args and these env vars differ.
# contribotlp runs the OTLP path's docs configs (otlp-<signal>.yaml);
# contribotlpeq the same with equal batching (otlpeq-<signal>.yaml).
arm_conf() {
  case "$1" in
    contribotlp)   echo "otlp-$2.yaml" ;;
    contribotlpeq) echo "otlpeq-$2.yaml" ;;
    *)             echo "$2.yaml" ;;
  esac
}
# Fixed-length host.name suffix per arm, so the arms' env tags stay apart in
# Datadog without giving any arm a longer hostname to send.
arm_suffix() {
  case "$1" in
    contrib) echo -b1 ;; contribotlp) echo -b2 ;; ddot) echo -b3 ;;
    ddotv2) echo -b4 ;; ddotdefault) echo -b5 ;; contribotlpeq) echo -b6 ;;
  esac
}
arm_image() { case "$1" in contrib*) echo "$CONTRIB_IMAGE" ;; *) echo "$DDOT_IMAGE" ;; esac; }
arm_args() {
  case "$1" in
    contrib*) echo "[\"--config=/conf/$(arm_conf "$1" "$2")\"]" ;;
    *)        echo "[\"run\", \"--config\", \"file:/conf/$2.yaml\"]" ;;
  esac
}
arm_env() {
  local pad="            "
  # Standalone DDOT asks the core Agent for its hostname and fails without one.
  # The node name is what contrib detects on its own.
  case "$1" in ddot*)
    echo "$pad- {name: DD_HOSTNAME, valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}" ;;
  esac
  # ddot and ddotv2 turn off DDOT's converter, which otherwise adds infraattributes,
  # cumulativetodelta, a self-telemetry scrape and the datadog extension to the
  # config. ddotdefault keeps the image defaults.
  case "$1" in ddot|ddotv2)
    echo "$pad- {name: DD_OTELCOLLECTOR_CONVERTER_FEATURES, value: none}" ;;
  esac
  # ddotv2 forces what contrib sends: v2 series with zlib, and gzip logs.
  if [ "$1" = ddotv2 ]; then
    echo "$pad- {name: DD_SERIALIZER_COMPRESSOR_KIND, value: zlib}"
    echo "$pad- {name: DD_USE_V3_API_SERIES_ENABLED, value: \"false\"}"
    echo "$pad- {name: DD_LOGS_CONFIG_COMPRESSION_KIND, value: gzip}"
  fi
  return 0
}

render_arm() {
  local arm="$1" signal="$2" name="bench-$1-$2"
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels: {app: bench, bench-arm: $arm, bench-signal: $signal}
spec:
  replicas: 1
  selector:
    matchLabels: {app: bench, bench-arm: $arm, bench-signal: $signal}
  template:
    metadata:
      labels: {app: bench, bench-arm: $arm, bench-signal: $signal}
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
            - {name: BENCH_ENV, value: bench-$arm}
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

kubectl -n "$NAMESPACE" rollout status deploy -l app=bench --timeout=300s >/dev/null \
  || warn "some benchmark collectors are not ready: kubectl -n $NAMESPACE get pods -l app=bench"

cat <<EOF

Benchmark is up: ${ARMS[*]}, LOCUST_USERS=$LOCUST_USERS, profiler=$PROFILER.
  Profiles:        Datadog Profiling, env:bench-profiler, by pod_name:bench-*
  Check v3 is on:  kubectl -n $NAMESPACE logs deploy/bench-ddot-metrics | grep -i v3
  Snapshot:        python3 -I $BENCH/measure.py start   (then: end, after the run)
  Report:          python3 -I $BENCH/report.py $BENCH/results/<run>
Sleep it afterwards: $DIR/down.sh   (sleeps the bench pool too)
EOF
