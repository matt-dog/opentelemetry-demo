# Astronomy Shop on the OTel Operator and kube-stack, with the DDOT Collector

A Datadog demo built on the familiar OpenTelemetry Demo, collected
by the DDOT Collector that the opentelemetry-examples kube-stack installer runs
(OTel Operator + kube-stack, ddot flow). The shop keeps its own Jaeger and Grafana;
Datadog gets everything. Runs on Rancher Desktop or on GKE.

Where it runs (Datadog org, keys, cluster, org settings, outside code) is in
`datadog/ENVIRONMENT.md`.

```
 Astronomy Shop services ──OTLP──> kube-stack DDOT daemon collector
   (upstream OTel SDKs)              (Operator-managed, ddot flow)
                                       ├─> Jaeger      (every trace)
                                       ├─> Prometheus  (metrics, span metrics: Grafana)
                                       └─> Datadog     (traces, metrics, logs)
```

## Changes from upstream

The current state is below; `datadog/CHANGES.md` is the dated log of every
change and why, including changes made by hand outside git.

Nothing in the upstream demo's source, images or chart is modified. Everything
is new files under `datadog/local/` that install the upstream chart (0.42.1)
and images with overrides:

| What | Upstream default | Here | Why |
|---|---|---|---|
| Collector | demo chart's bundled otelcol-contrib | off; kube-stack DDOT daemon collector (Operator-managed, ddot flow) | the point of the demo |
| Service OTLP target | `otel-collector` | `OTEL_COLLECTOR_NAME` = kube-stack daemon service | route every service to DDOT |
| Jaeger, Prometheus | fed by the bundled collector | fed by the DDOT collector (`kube-stack-values.yaml`) | shop UI and Grafana keep working |
| OpenSearch | on | off | logs go to Datadog |
| load-generator OTLP endpoint | `:4318` | `:4317` | its exporter is gRPC; at :4318 every export failed, its parent spans were lost, and one user flow showed as many root traces |
| Jaeger memory | 600Mi, 25,000 traces | 1536Mi, 10,000 traces | OOM-killed under checkout traffic, losing every stored trace |
| Feature flags (set by `up.sh`, live in flagd) | all off | paymentFailure 50%, cartFailure 100%, productCatalogFailure on for OLJCESPC7Z | error traces; the shipped productCatalogFailure rule returns "off" on both branches |
| Host Profiler | none | kube-stack `host-profiler` DaemonSet (DDOT preview image), on by default for `up.sh gke` (`DD_HOST_PROFILER_ENABLED`) | profiles from the same cluster |
| `shopper` (new pod) | none | headless Chromium placing an order every 20 s | checkout traces that start at the browser click (`frontend-web`) |
| `contrib` Collector (new) | none | upstream collector-contrib 0.161.0 (`contrib-collector.yaml`): `postgresql`, `redis`, `kafka_metrics` receivers | integration dashboards; the DDOT Collector does not ship those receivers; an upstream row next to DDOT in Fleet Automation |
| fraud-detection SDK | upstream OTel Java agent | the DDOT SDK (Java 1.67-preview), swapped in by an init container (`values-local.yaml`) | Act 2: one Kafka trace across upstream SDKs and the DDOT SDK; `ad` stays upstream for Act 1's trace-to-logs |
| Metric tags | Datadog names only (`pod_name`, `kube_cluster_name`) | OTel names too (`metrics.resource_attributes_as_tags`) | filter metrics by `k8s.cluster.name` and the rest |
| `scenarios` (new pod) | flags changed by hand | holds flags to a schedule in `scenarios.yaml`: `adHighCpu` on from :30 to :45 each hour, UTC | a problem at known times with a quiet baseline between, for anomaly monitors and screenshots |
| ad CPU limit | none | 300m | adHighCpu throttles the JVM, so GetAds slows; with no limit its load threads take spare cores and requests stay at a few ms |
| agent LLM | recorded responses for three prompts | Claude Haiku 5.5 through LangChain's Anthropic client (`llm.py` replaced from a ConfigMap) | real tokens and cost in Agent Observability |
| RUM | none | Datadog Browser SDK added to the shop's and chatbot's pages by an Envoy Lua filter (`frontend-proxy/envoy.tmpl.yaml`) | RUM, Session Replay, user action to backend trace |
| Datadog monitors and log index | none | `datadog/` templates applied by `dd-apply.py` (run by `up.sh`): the ad latency monitors, the RUM application, and a log index for the env ahead of `main` | the setup is rebuilt from git in any env or org; `${ENV_NAME}` is filled in per env |

Known issues not fixed: the quote service's (PHP) spans start about 154 s
before their shipping parent in Rancher Desktop, which stretches checkout
traces to 2.6 minutes; the ad service's failure records no exception type or
stack.

## Run it

Needs `gcloud` signed in, Helm, and the keys: `op` signed in, or `DD_API_KEY`, `DD_APP_KEY` and
`ANTHROPIC_API_KEY` set in the environment (read once each). The kube-stack installer is copied
into `kube-stack/` (`KUBE_STACK_DIR` overrides the path).

```bash
datadog/local/up.sh local   # Rancher Desktop: about 12 GB for the VM
datadog/local/up.sh gke     # GKE otel-demo in dd-dev-otelpmdev, created if missing
```

Then port-forward `svc/frontend-proxy` 8080 (up.sh prints the command):

- Shop: http://localhost:8080, flags at http://localhost:8080/feature
- Jaeger: http://localhost:8080/jaeger/ui
- Grafana: http://localhost:8080/grafana
- Datadog: APM, `env:otel-demo-local` or `env:otel-demo`

Delete the GKE cluster when done:
`gcloud container clusters delete otel-demo --project dd-dev-otelpmdev --zone us-east1-b`

## Files

- `kube-stack-values.yaml`: overlay for the kube-stack installer. The daemon
  collector also exports traces to the shop's Jaeger, and metrics plus span
  metrics to its Prometheus, and accepts browser OTLP (CORS).
- `values-local.yaml`: the demo chart with its bundled Collector off and
  `OTEL_COLLECTOR_NAME` pointing every service at the kube-stack collector.
- `shopper.yaml`: the headless browser shopper; `up.sh` applies it.
- `scenarios.yaml`: the flag schedule and the pod that keeps it; `up.sh` applies it.
- `datadog/`: monitor and log index definitions, templated on `${ENV_NAME}`.
- `dd-apply.py`: creates or updates them (monitors matched by name, tagged
  `managed_by:otel-demo-local`). Needs `DD_APP_KEY` (`DD_APP_KEY_REF`, default
  `op://Employee/ddot-lab/matt-dog-dd-app-key`) with write access; each object
  that is refused is skipped with a warning.
- `kube-stack/`: the kube-stack installer, copied from opentelemetry-examples
  (where from, and why, in its README).
- `contrib-collector.yaml`: the upstream Collector for PostgreSQL, Redis and Kafka metrics; `up.sh` applies it.
- `stage.sh`: starts and stops the Act 1 problem on cue (`start`, `stop`, `status`).
- `flags.py`: reads and sets feature flags through flagd-ui's API, the only safe way (`get`, `set`, `target-product`).
- `remediator.yaml`: Act 3's endpoint for Datadog Workflow Automation, with its Ingress, certificate and Cloud Armor link.
- `up.sh`: runs the installer and the demo chart against a kubeconfig holding
  only the target cluster, then sets the failure flags.

## Notes

- Traces come from the shop's upstream OpenTelemetry SDKs through the DDOT
  Collector. The Operator does not inject the DDOT SDK here: the shop's images
  already carry OTel SDKs, and injecting would instrument them twice.
- The collector image is the one the kube-stack ddot flow pins (a DDOT dev build
  at the time of writing), not a released DDOT Collector.
- Swapping the demo chart's own Collector for the released DDOT Collector 7.84.3
  (tried first, 2026-10-15) took more than two lines: an empty `command.name`
  (the chart runs `/otelcol-contrib`), no `service.profilesSupport` gate,
  `DD_HOSTNAME`, and a new config, because the demo's uses five components DDOT
  7.84.3 does not ship (`kafkametrics`, `redaction`, `gen_ai_normalizer`,
  `opensearch`, `opamp`) plus a profiles pipeline.
- Fixes over the chart defaults, in `values-local.yaml`: the load generator
  exports over gRPC but the chart points it at :4318, so its parent spans were
  lost and each user flow showed as several root traces; Jaeger's 600Mi limit
  OOM-killed it (and lost every trace) under checkout traffic.
- Failure flags up.sh sets: `paymentFailure` 50% (Node, exception with stack),
  `cartFailure` 100% (.NET, redis error with stack, inside a successful
  checkout), `productCatalogFailure` for product OLJCESPC7Z (Go; the shipped
  rule returned "off" on both branches). `adFailure` is left off: the ad service
  records no exception type or stack, so Datadog shows "Missing error message".
- ddstaging logs (handled by `datadog/log-index.json`): app logs fall through to the `main` index, whose "Reduce
  volume" exclusion drops 99.99%, so they don't link to traces until an index
  ahead of `main` matches this env. The matt-dog org has no such exclusion.
