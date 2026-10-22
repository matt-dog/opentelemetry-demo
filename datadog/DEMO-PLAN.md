# Demo plan: OpenTelemetry on Datadog, no Agent

Status: approved by Matthew 2026-10-22; items 1 to 6 built and verified through the Datadog
API the same day (see `DEMO-SCRIPT.md` for what to check by eye). Replaces the 2026-10-18 re:Invent
tour plan (ddstaging, `env:otel-demo-gke-blog`), which is in git history.
Every change made from this plan gets an entry in `CHANGES.md`. The presenter's
walkthrough, with links, is `DEMO-SCRIPT.md`.

## Audience and message

An OpenTelemetry-first customer, often unwilling to run the Datadog Agent. Two things
to land:

1. Their OpenTelemetry data works natively in Datadog, with the names they already use
   (semantic conventions, OTel attribute names in every filter), and no Agent.
2. Each DDOT component (SDK, Host Profiler, Collector) swaps in for its upstream
   counterpart and adds something, one at a time, and swaps back.

Positioning follows the DDOT Product Messaging doc: lead with "your OTel works here",
then "more when you want it", never "OTel is not enough". The demo is the live part of
the customer deck (Oct 2026), slide 9 ("An investigation across every OpenTelemetry
signal") and slides 18 to 24 (DDOT).

## Act 1: the investigation, upstream OTel SDKs, no Agent

| Step | What the audience sees | Built from |
|---|---|---|
| 1. Alert | A monitor on ad p95 latency fires; the `adHighCpu` change event is on it | `ad-latency-threshold` monitor (the anomaly monitor joins once it has a day of history), `scenarios` change events |
| 2. Service page | p95 jumps from about 15 ms to about 300 ms | APM on the upstream Java agent |
| 3. Trace | A slow GetAds span; its container at the 300m CPU limit | APM, Kubernetes metrics filtered by OTel names |
| 4. Logs | The span's log: "High CPU-Load problempattern enabled" | ad's own log line, inside the request, with trace context |
| 5. Profile | Host Profiler: `Logarithmizer.run` burning CPU in the ad JVM | DDOT Host Profiler (no trace link yet; slide 22 says "Coming Soon") |

Semantic conventions throughout: filter by `service.name`, `deployment.environment.name`,
`k8s.pod.name`, `k8s.cluster.name`, in traces and in metrics.

## Act 2: DDOT over upstream

- **DDOT SDK** on `fraud-detection` (Kafka consumer, JVM). Checkout (upstream Go SDK)
  produces to Kafka, fraud-detection (DDOT SDK) consumes: one trace across both SDKs.
  `ad` stays on the upstream agent so Act 1's trace-to-logs keeps working.
- **DDOT Host Profiler**: every process profiled with no code change, including Postgres,
  Kafka and Envoy.
- **DDOT Collector**: Fleet Automation, next to an upstream contrib Collector.
- **Swap in, swap back**: slide 24's three-line diff; the same trace in Jaeger.

## Side trips, all without an Agent

- Kafka context propagation (above). Data Streams Monitoring needs the Agent; left out.
- Database spans with their query text. Full DBM needs the Agent; left out.
- Integration dashboards for PostgreSQL, Redis (Valkey) and Kafka, from an upstream
  contrib Collector: the DDOT Collector does not ship those receivers. That Collector
  also gives Fleet Automation an upstream row and shows a mixed pipeline.
- RUM, with the Datadog Browser SDK (a Datadog component, though no Agent).
- LLM Observability on the shop's agent (Claude).

## Work, in order

1. OTel attribute names on metrics: the Datadog exporter's
   `metrics.resource_attributes_as_tags`, so `k8s.cluster.name` and the rest filter
   metrics (until now they mapped to `kube_cluster_name` and similar only).
2. Act 1 verified end to end in matt-dog, step by step.
3. Stage cue: `local/stage.sh` starts the problem on demand, with its change event, and
   hands back to the schedule after.
4. DDOT SDK on fraud-detection, verified in one trace with checkout.
5. Upstream contrib Collector for PostgreSQL, Redis and Kafka metrics; check which
   dashboards light up.
6. `DEMO-SCRIPT.md`: the walkthrough with direct links for each step.
7. Later: the anomaly monitor once it has history (about a day); a presenter dashboard.

## Act 3: auto-remediation (approved 2026-10-22)

The monitor that opens Act 1 also starts a Datadog workflow that fixes the problem twice:
first the symptom, then the cause.

1. **Raise ad's CPU limit** (Kubernetes patch on the `ad` deployment): latency recovers in
   about a minute, but the load threads are still running.
2. **Roll back the change behind the alert**: `adHighCpu` back to off through flagd-ui's
   API, the same change the event on the monitor names. That is the real fix.
3. Post a change event for each action, so the service page shows what the workflow did.

How it is built:
- A standalone **Private Action Runner** in the cluster (Helm chart
  `datadog/private-action-runner`), enrolled with the API and app keys from a one-off Job.
  It only connects out to Datadog. It is a Datadog component (not the Agent), so it is
  presented as optional, like the Agent on slide 20.
- The workflow is defined in git (`local/datadog/workflow-remediate-ad.json`) and applied by
  `dd-apply.py`; the monitor's message mentions it.
- **Stage mode only.** The hourly schedule fires the same monitor, and a remediation then
  would fight the schedule (it turns the flag back on within 30 s). The workflow's first step
  reads the scenarios deployment: paused (`stage.sh start`) means act, running means stop.
- `stage.sh stop` puts ad's CPU limit back to 300m, so a live patch never drifts from git.
- The CPU step **removes** the limit (keeping a 300m request) rather than raising it. Measured
  2026-10-22: at a 2-core limit p95 was still 18 to 46 ms with the pod using 1.8 cores (the four
  load threads take any ceiling), and a 6-core limit could not schedule, because without an
  explicit request Kubernetes sets the request equal to the limit.

Status 2026-10-22, paused at Matthew's request:
- Done: runner `otel-demo` installed (Helm release `par` in `otel-demo`, `local/par-values.yaml`);
  connections `otel-demo kubernetes` and `otel-demo flagd`; workflow published from git
  (`workflow-remediate-ad.json`, applied by `dd-apply.py`); the monitor mentions it on Alert.
- Not done: one end-to-end run (cue, Alert, workflow, recovery, rollback, events); `up.sh`
  does not yet enroll and install the runner or create the connections (done by hand once,
  see CHANGES.md); the runner identity lives only in that Helm release, so a new cluster needs a
  new enrollment and connections.


## Known limits

- The collector images are dev builds pinned by the kube-stack ddot flow, not released
  DDOT versions; slide 24 names released tags.
- The ad load threads are unnamed (`Thread-N`); naming them means changing upstream code.
- No trace-to-profile link yet (Host Profiler preview).
- The DDOT exporters' own host metadata still reports `<node>.dd-dev-otelpmdev`, so the host
  list shows each node a second time with only `otel` on it, and Fleet Automation uses that name.
- The DDOT SDK's own logs still don't reach Datadog (why `ad` stays upstream).
- No Datadog OTel dashboard for Redis yet (slide 26 roadmap); its metrics arrive.
- Session Replay: no session has a replay. The Browser SDK (7.16.1, CDN) logs "Recorder failed to
  start ... Failed to resolve module specifier './chunks/datadogRecorder-...'", also on a bare
  test page, in the shopper's headless Chromium 129. Not yet checked in a regular Chrome; if it
  works there, only synthetic sessions are affected.
