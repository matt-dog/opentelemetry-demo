# Demo script: OpenTelemetry on Datadog, no Agent

The live part of the OpenTelemetry customer deck (Oct 2026): slide 9 for Act 1, slides
18 to 24 for Act 2. The plan and the reasons behind it are in `DEMO-PLAN.md`; the
environment (org, cluster, keys) is in `ENVIRONMENT.md`.

Every link opens the matt-dog org on datad0g.com, env `otel-demo`. No Datadog Agent
runs anywhere in the cluster: the shop's services use upstream OpenTelemetry SDKs
(fraud-detection uses the DDOT SDK), the collectors are the DDOT Collector plus one
upstream contrib Collector, and profiles come from the DDOT Host Profiler.

Verified on 2026-10-22 through the Datadog API (numbers below are from that run): the data
behind every link is there. The links themselves were built from those queries but not
yet opened in a browser, so click through each once before the first presentation and fix
any route that has moved. Rows marked "check once" were not visible to the API at all.

## Before you start

| When | Do |
|---|---|
| Day before | `datadog/local/up.sh gke` if the cluster is down (10 to 15 min) |
| 10 min before | `datadog/local/stage.sh start` (turns `adHighCpu` on, posts the change event, pauses the schedule) |
| 5 min before | Open the monitor link below; it should be in Alert |
| After | `datadog/local/stage.sh stop` (between :30 and :45 UTC the schedule keeps the problem on) |

No cue needed between :30 and :45 past each hour, UTC: the schedule runs the same
problem then. Shop UI, if you want it: `kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080`,
then http://localhost:8080 (Jaeger at /jaeger/ui, flags at /feature).

## Act 1: an investigation on upstream OpenTelemetry (slide 9)

Say up front: everything in this act comes from the OpenTelemetry SDKs the demo
ships with, through OTLP, with no Datadog Agent.

**1. The alert.** [link](https://app.datad0g.com/monitors/35243022)
- The ad service's per-minute p95 latency is over 20 ms; its baseline is 3 to 6 ms, and
  the problem takes it to 35 to 130 ms.
- The change event "adHighCpu on (ad)" sits on the monitor's graph: a feature-flag
  flip, posted by the stage script. All events for the service: [link](https://app.datad0g.com/event/explorer?query=service%3Aad%20env%3Aotel-demo)
- The anomaly monitor ([link](https://app.datad0g.com/monitors/35241062)) is the slide's story. It needs about a day of
  history before its baseline is trustworthy; until then lead with the threshold one.

**2. The service page.** [link](https://app.datad0g.com/apm/services/ad/operations/grpc.server.request/resources?env=otel-demo)
- p95 on GetAds goes from about 3 ms to 35 to 130 ms at the flag flip. The marker
  on the graph is the same change event.

**3. The slow trace, searched with OpenTelemetry names.** [link](https://app.datad0g.com/apm/traces?query=service.name%3Aad%20deployment.environment.name%3Aotel-demo%20resource_name%3A%22GetAds%20oteldemo.AdService%22%20%40duration%3A%3E50ms)
- The query is `service.name:ad deployment.environment.name:otel-demo`: OTel attribute
  names, as they arrive. Same with `k8s.deployment.name:ad rpc.method:GetAds`: [link](https://app.datad0g.com/apm/traces?query=k8s.deployment.name%3Aad%20rpc.method%3AGetAds)
- Open a trace: frontend calls `GetAds` (about 100 ms), and its only child,
  `getAdsByCategory`, takes 0.1 ms. The time is not in the code path.
- The container: [link](https://app.datad0g.com/metric/explorer?exp_metric=container.cpu.usage%2Ck8s.container.cpu_limit&exp_scope=k8s.deployment.name%3Aad&exp_agg=avg&exp_row_type=metric)
  `container.cpu.usage` sits at 0.3 cores, on its `k8s.container.cpu_limit` of 0.3.
  Every name in that query is an OpenTelemetry name (semantic mode is on in this org).

**4. The logs for that span.** From the trace, open the Logs tab; or [link](https://app.datad0g.com/logs?query=service%3Aad%20%22High%20CPU-Load%20problempattern%20enabled%22)
- "High CPU-Load problempattern enabled", logged by the ad service inside that very
  request, carrying its trace ID (OTLP logs from the upstream Java agent).

**5. The profile.** [link](https://app.datad0g.com/profiling/explorer?query=service%3Aad%20env%3Aotel-demo)
- The DDOT Host Profiler, an eBPF profiler with no code change and no SDK: the ad
  JVM's CPU goes to `Logarithmizer.run` threads (the demo names them `Thread-N`).
  Profiles for the ad JVM arrive in this org (checked 2026-10-22); the function view
  was last checked by eye in ddstaging on 2026-10-18, so look once before presenting.
- Compare with a time before the flag flip to show the one new function.
- Honest note: linking a span straight to its profile is "Coming Soon" (slide 22),
  so the jump is by service and time.

## Act 2: more when you want it, with DDOT (slides 18 to 24)

**The DDOT SDK, mixed with upstream SDKs in one trace.** [link](https://app.datad0g.com/apm/traces?query=service%3Afraud-detection%20env%3Aotel-demo)
- Open a trace: 44 spans, 11 services in 8 languages. Checkout (upstream Go SDK)
  publishes to Kafka, `orders`; fraud-detection consumes it on the DDOT SDK. One
  trace, W3C context through Kafka headers, no Agent.
- Every span from the DDOT SDK: [link](https://app.datad0g.com/apm/traces?query=env%3Aotel-demo%20telemetry.sdk.name%3Adatadog) (`telemetry.sdk.name:datadog`).
- The swap is the init container and `JAVA_TOOL_OPTIONS` in
  `datadog/local/values-local.yaml` (slide 24's first diff). Delete the block to swap back.

**The DDOT Host Profiler: every process.** [link](https://app.datad0g.com/profiling/explorer?query=env%3Aotel-demo)
- PostgreSQL, Kafka, Envoy, Chrome in the shopper, the collectors themselves: all
  profiled from the host, none of them instrumented.

**The DDOT Collector, next to an upstream one.** [link](https://app.datad0g.com/fleet)
- Fleet Automation lists the DDOT Collectors (one per node) and `contrib`, an upstream
  collector-contrib 0.161.0 run by the same OpenTelemetry Operator, reporting through
  its datadog extension. Check the `contrib` row in the UI before presenting: the
  Fleet API confirmed only the DDOT ones on 2026-10-22. Mixed pipelines
  are supported (slide 17).
- Why the upstream one is there: the DDOT Collector ships a curated set of
  components, without the PostgreSQL, Redis or Kafka metrics receivers. Bring your
  own Collector for those, or build a custom DDOT (slide 23).

**Swap in, swap back.** Slide 24's diff, then the same trace in Jaeger:
http://localhost:8080/jaeger/ui (port-forward above), search the trace ID of the
Kafka trace. Same 44 spans, same DDOT SDK span: the data is standard OTLP.

## Side trips, all without an Agent

| Topic | Link | What to say |
|---|---|---|
| Kubernetes | [link](https://app.datad0g.com/orchestration/explorer/pod?query=kube_cluster_name%3Aotel-demo) | Kubernetes Explorer from the OTel k8s receivers (slide 11) |
| Metrics by OTel names | [link](https://app.datad0g.com/metric/explorer?exp_metric=k8s.container.cpu_limit&exp_scope=k8s.cluster.name%3Aotel-demo%2Ck8s.namespace.name%3Aotel-demo&exp_group=k8s.deployment.name&exp_agg=avg&exp_row_type=metric) | `k8s.cluster.name`, `k8s.namespace.name`, `k8s.deployment.name` as metric tags |
| PostgreSQL dashboard (check once) | [link](https://app.datad0g.com/dashboard/lists?q=PostgreSQL) | From the upstream `postgresql` receiver; PostgreSQL Overview and Metrics |
| Kafka dashboard (check once) | [link](https://app.datad0g.com/dashboard/lists?q=Kafka) | From the upstream `kafka_metrics` receiver; consumer lag per group |
| Redis (Valkey) | [link](https://app.datad0g.com/metric/explorer?exp_metric=redis.clients.connected%2Credis.commands&exp_scope=k8s.cluster.name%3Aotel-demo&exp_agg=avg&exp_row_type=metric) | Metrics arrive; no Datadog OTel Redis dashboard yet (slide 26 roadmap) |
| Kafka propagation | [link](https://app.datad0g.com/apm/traces?query=service%3Afraud-detection%20env%3Aotel-demo) | Producer and consumer spans in one trace (Data Streams Monitoring needs the Agent) |
| Database spans | [link](https://app.datad0g.com/apm/traces?query=env%3Aotel-demo%20%40db.system.name%3Apostgresql) | product-catalog's PostgreSQL spans carry the full statement (`db.system.name`, current semantic conventions); cart's Valkey spans carry the command. Full DBM needs the Agent |
| RUM | [link](https://app.datad0g.com/rum/sessions?query=%40application.id%3A8d3ef4e9-394d-4519-9cbe-aeee1a60d120) | A browser click to its backend trace (Datadog Browser SDK, which is not the Agent) |
| LLM Observability | [link](https://app.datad0g.com/llm/traces) | The shop's agent on Claude, with tokens and cost (slide 13) |

## If something looks wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| Monitor OK during the problem | The problem started under 2 minutes ago | Wait; or check `stage.sh status` |
| Problem won't stop | Between :30 and :45 UTC the schedule holds it on | Expected; it ends at :45 |
| Trace search empty for older traces | Retention filter missing | `dd-apply.py` (run by `up.sh`) creates "otel demo: every span" |
| No profiles for a service | Host Profiler pods not Running | `kubectl -n opentelemetry-operator-system get pods` |
