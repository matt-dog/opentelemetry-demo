# Changes from the upstream OpenTelemetry Demo

A running log of how this fork (matt-dog/opentelemetry-demo, branch
`ddot-local-blog`) differs from upstream (open-telemetry/opentelemetry-demo), and
why. Newest first. The README tables describe the current state; this file keeps
the history.

Nothing in the upstream source, images or Helm chart is modified. Every
difference is a new file under `datadog/`, or one of the few lines in
`.gitignore`, or an override passed to the upstream chart (0.42.1). Check with:

```bash
git diff --stat upstream/main...ddot-local-blog
```

Add an entry with every commit that changes the difference, and record changes
made by hand outside git under "Live changes not in git" until they are moved
into git or undone.

## Live changes not in git

| Date | Where | Change | Why | Status |
|---|---|---|---|---|
| 2026-10-18 | ddstaging log index `ddot-lab` (UI) | Filter widened to also match `env:otel-demo-gke-blog` app services | App logs fell through to `main`, which drops 99.99% | Redundant since `fc642ea5` (the env has its own index, first in order); can be reverted to `env:ddot-lab service:orders-*` |

## Log

### 2026-10-18 · `fc642ea5` · Datadog monitors and log index from git
- **What:** `local/datadog/` holds a monitor and a log index as templates on
  `${ENV_NAME}`; `local/dd-apply.py` creates or updates them, and `local/up.sh`
  runs it.
  - Monitor: ad service p95 latency anomaly (`basic`, 3 bounds, above, 3-minute
    window, 80% threshold, no notification targets).
  - Log index: one per env, app services only, 7 days, 1M a day, first in the
    index order.
- **Why:** so the Datadog side is rebuilt from git in any env or org instead of
  by hand. The log index replaces the `ddot-lab` filter edit above.
- **Notes:**
  - The monitor first existed by hand (id 334059057), and `dd-apply.py` adopted
    it by name.
  - `basic` adapts to a new level within about 4 minutes, so the alert window
    is 3 minutes (5 minutes at 100% missed the 20:30Z run). It alerts at onset
    and recovers while latency is still high.
  - `agile` and `robust` need more history than a new cluster has.

### 2026-10-18 · `4cd12436` · Problem scenarios on a clock; ad CPU limit
- **What:** `local/scenarios.yaml` is a pod that holds flags to a schedule
  through flagd-ui's API (`adHighCpu` on from :30 to :45 each hour, UTC).
  `local/values-local.yaml` gives ad a 300m CPU limit.
- **Why:**
  - Flags had been flipped by hand with `kubectl exec`, with no record and no
    baseline. Upstream's flagd-ui scheduler picks flags at random and keeps its
    settings only in memory.
  - With no CPU limit, `adHighCpu` used spare cores and GetAds stayed at a few
    ms. With 300m, the JVM is throttled and p95 goes from about 2.7 ms to about
    100 ms.

### 2026-10-18 · `5096449d` · Blog demo on GKE, host profiler, Playwright shopper
- **What:**
  - `local/up.sh` takes `local` or `gke`; the `gke` target creates cluster
    `otel-demo-blog`, env `otel-demo-gke-blog`.
  - The kube-stack Host Profiler is on for GKE.
  - `local/shopper.yaml` adds a headless Chromium that orders every 20 s.
  - The load generator exports to :4317, and Jaeger gets 1536Mi and 10,000
    traces.
  - `up.sh` sets paymentFailure 50%, cartFailure 100%, and productCatalogFailure
    for OLJCESPC7Z.
- **Why:**
  - The blog's screenshots needed profiles, and checkout traces that start at a
    browser click (`frontend-web`). The Locust load generator doesn't run the
    shop's JavaScript.
  - The chart points the load generator at :4318 while it exports gRPC, so its
    parent spans were lost.
  - Jaeger at 600Mi was OOM-killed and lost every stored trace.
  - The shipped productCatalogFailure rule returns "off" on both branches.

### 2026-10-15 · `453d8bd0` · Astronomy Shop on the OTel Operator and kube-stack with DDOT
- **What:** `local/` turns the chart's bundled Collector off. Every service
  sends to the DDOT daemon collector that the opentelemetry-examples kube-stack
  installer runs, and an overlay (`kube-stack-values.yaml`) keeps Jaeger and
  Grafana fed. OpenSearch is off.
- **Why:** the DDOT launch blog shows Jaeger and Datadog fed from the same
  DDOT Collector.

### 2026-09-30 · `601c9c7b` · Container and Kubernetes tags on spans
- **What:** every service's `OTEL_RESOURCE_ATTRIBUTES` carries
  `k8s.container.name` and `k8s.pod.uid`. `k8s_attributes` extracts
  `container.id`, and GKE nodes get `kube_cluster_name` as a host tag.
- **Why:** spans had no `container.id`, so Datadog attached no container tags,
  and filtering APM by `kube_cluster_name` matched nothing.

### 2026-09-29 · `fd955772` · Datadog deployment for the demo on GKE
- **What:**
  - `my-values-file.yml`: chart overrides adding the otlp_http exporter and the
    span_metrics connector beside the chart's Jaeger, Prometheus and OpenSearch
    pipelines, plus host metrics, cAdvisor, Postgres metrics and tagged
    container logs.
  - `cluster-collector.yaml`: a single-replica collector for Kubernetes
    Explorer, kube-state-metrics and Kafka metrics.
  - `frontend-lb.yaml`: a LoadBalancer limited to allowed CIDRs.
  - `up.sh`, `down.sh`, `status.sh`.
  - `.gitignore`: `datadog/.env` and a local backup folder.
- **Why:** to run the demo on GKE and send traces, metrics, logs and Kubernetes
  data to Datadog over OTLP, following Datadog's documented setup for a
  self-managed Collector. `/feature` is on the same URL as the shop, so the
  LoadBalancer is restricted. The kafkametrics receiver needs a single replica.
