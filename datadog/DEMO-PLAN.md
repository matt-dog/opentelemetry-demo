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

## Act 3: auto-remediation (approved 2026-10-22; redesign pending)

The monitor that opens Act 1 also starts an automatic fix, twice: first the symptom (lift ad's
CPU limit, keeping a 300m request), then the cause (roll back `adHighCpu`), with a change event
for each. Stage mode only, so the hourly schedule never fights it.

No Private Action Runner (Matthew, 2026-10-23: it is Agent-based). A first build used one; it
was removed the same day (CHANGES.md). Without it, Datadog cannot reach into the cluster, so
something of ours does the Kubernetes work. Matthew chose (2026-10-23) Workflow Automation calling
a small public endpoint of ours over HTTPS (over a remediator that polls Datadog).

Design:
- **`remediator`** (`local/remediator.yaml`): a stdlib Python service in `otel-demo` with three
  narrow endpoints: `GET /stage` (stage mode, flag, ad's CPU limit), `POST /lift-cpu-limit`,
  `POST /rollback-flag`. Each action refuses outside stage mode and posts a change event
  (`service:ad`, like `scenarios`). Kubernetes access through a Role: get and patch on deployments
  in `otel-demo` only.
- **Exposure, in layers:** a GKE Ingress on a reserved global static IP, HTTPS with a
  Google-managed certificate for `<ip>.sslip.io` (no DNS zone needed); a Cloud Armor policy that
  admits only Datadog's `webhooks` IP ranges for the site (three /25s on datad0g.com); a bearer
  token, random per cluster, in a Kubernetes secret and in a Datadog token-auth HTTP connection,
  never in git or in the workflow.
- **Workflow** (`local/datadog/workflow-remediate-ad.json`, applied by `dd-apply.py`): monitor
  trigger, `GET /stage`, then if in stage mode `POST /lift-cpu-limit`, wait 120 s,
  `POST /rollback-flag`. The monitor mentions it on Alert.
- `up.sh` reserves the IP, creates the Cloud Armor policy and the token if missing, and applies it.

Status 2026-10-23: built and verified. Run by hand in stage mode, every step succeeded and p95
went from about 102 ms to 7 to 15 ms; outside stage mode it checks and stops. Started by the monitor itself on cue, the whole
loop (alert, lift, rollback, monitor OK) took about 7.5 minutes. Requests from
outside Datadog's ranges get 403 from Cloud Armor; without the token, 401.

Measured 2026-10-22 and still true for either: raising the limit does not fix latency (2 cores:
p95 18 to 46 ms, the pod at 1.8 cores; the four load threads take any ceiling), and without an
explicit request Kubernetes sets request equal to limit, so a high limit cannot schedule.
`stage.sh stop` already restores git's 300m limit.

## Findings that shape the script (2026-10-23)

- Change tracking gets feature-flag changes only from Datadog Feature Flags, LaunchDarkly or the
  Events API; there is no OTLP route, and OpenTelemetry has no convention for flag changes (only
  `feature_flag.evaluation`, Release Candidate). So the change event stays an Events API call,
  and the script says so.
- The flag is in the OTLP data anyway: ad's `resolve` spans carry `feature_flag.key: adHighCpu`
  and flagd's `resolveBoolean` spans add `feature_flag.result.variant` (off/on), the OTel
  convention. Grouping those spans by variant over time shows the flip in pure OTel data.
- The service page had no incidents, monitors of its own or SLOs because none existed. The
  workflow now declares an incident, and `dd-apply.py` builds two SLOs and an error-rate monitor
  (`local/datadog/slos/`, `monitors/ad-error-rate.json`), all on the OTel-derived trace metric.
- The anomaly monitor is not ready to lead step 1: in its first 24 hours, 13 of 25 triggers fell
  in the problem windows and 12 were false alarms. The hourly schedule also teaches a seasonal
  algorithm that the spike is normal. The threshold monitor leads until that is resolved.

## Problem patterns (tested 2026-10-24)

Five flags ran together for about 2h20m (02:29 to 04:52 UTC, after a test script stalled), each
compared with the hour before:

| Flag | Result | Story |
|---|---|---|
| `adHighCpu` | works (main flow) | monitor, trace, CPU limit, logs, profile, workflow |
| `paymentFailure` 25% | works: payment error rate 7% to 26% | Error Tracking: exception with stack |
| `imageSlowLoad` 5s | works in the browser: RUM image load p95 0.14 s to 5.09 s | RUM: slow page, user impact |
| `aiRunawayAgent` | scheduled since 2026-10-19 | LLM Observability |
| `cartFailure` 10% (was 100%) | on all the time | errors inside a successful checkout; at 100% no order reached Kafka |
| `intlShippingSlowdown` 5s | evaluated, no effect: only international orders, and the shoppers order domestically | needs an international order |
| `kafkaQueueProblems` | works (2026-10-25): fraud-detection lag 0 to 909 in 3 min, drains in a minute | Kafka: consumer lag, DDOT SDK consumer |
| `productCatalogLockContention` | works after a grant (2026-10-25): product-catalog p95 21 ms to 26.8 s; slows the whole shop | Postgres: lock span, locks metric, integration dashboard |
| `emailMemoryLeak` 10000x | works (2026-10-25): OOMKilled in about 40 s; 1000x only grows memory | Kubernetes: restarts, OOMKilled reason |

Scheduled now, all in :30 to :45: the seven working flags above (ENVIRONMENT.md). Each is a chapter on its own service and Datadog product, all from OTel data.

## Shared demo (2026-10-24)

No stage mode: the demo serves many presenters at once, any time. Everything runs on the hourly
clock, the workflow acts on every alert, and presenters either catch the live :30 to :45 window or
pin a past one. `stage.sh` is now for testing changes only. Incidents follow option B (at most one
open for ad, never resolved) until there is an Incident Management seat. The scheduler holds
the baseline flags, so a flagd restart (for example a GKE node upgrade) no longer loses them.
GKE upgrades the cluster automatically (REGULAR channel) and recreated every node at 17:26 UTC on
2026-10-24; upgrades are now held to a daily 06:00 to 10:00 UTC maintenance window. Open issues: CHANGES.md,
2026-10-24, Shared, always-on demo.

## Incidents, unattended (built, off)

Goal: an incident lives exactly as long as the latency alert, so the unattended demo shows real
time-to-detect and time-to-resolve and service health returns to OK between windows. Needs an
Incident Management seat for Matthew (the workflows' owner). To switch on:
1. In `workflows/remediate-ad.json`, move `Declare_incident` ahead of `Stage_mode` (declare on
   every alert; remediation stays stage-only, since the schedule would re-enable the flag).
2. Add `{{#is_recovery}}@workflow-otel-demo-resolve-ad-incident{{/is_recovery}}` to the latency
   monitor's message; `workflows/resolve-ad-incident.json` resolves the newest active ad incident.
3. Resolve incidents #1 and #2 (left open by the 2026-10-23 test).
About 24 incidents a day, all resolved; open them every few hours instead if that is too many.

## Known limits

- The collector images are dev builds pinned by the kube-stack ddot flow, not released
  DDOT versions; slide 24 names released tags.
- The ad load threads are unnamed (`Thread-N`); naming them means changing upstream code.
- No trace-to-profile link yet (Host Profiler preview).
- The Host Profiler undercounts ad's CPU during the window by about 100 times: on 2026-10-28 it showed
  152 ms of CPU a minute for 18:29 to 18:37 UTC, while the container used 0.30 cores (about 18 s a
  minute). The function is right: `CPULoad$Logarithmizer.run` appears only in the window (comparison on
  pod `ad-66c6794c6-dr5xd`, 17:38 to 17:45 against 18:29 to 18:37). Step 6 points at the function, never
  the totals. APM's Profiling page shows no profiles for ad (continuous profiler not enabled); the pod's
  Profiles tab in Kubernetes Explorer does.
- The DDOT exporters' own host metadata still reports `<node>.dd-dev-otelpmdev`, so the host
  list shows each node a second time with only `otel` on it, and Fleet Automation uses that name.
- The DDOT SDK's own logs still don't reach Datadog (why `ad` stays upstream).
- No Datadog OTel dashboard for Redis yet (slide 26 roadmap); its metrics arrive.
- Resolving the workflow's incident needs an Incident Management seat (403 "Seat Required"); the
  declare step works without one.
- Session Replay: no session has a replay. The Browser SDK (7.16.1, CDN) logs "Recorder failed to
  start ... Failed to resolve module specifier './chunks/datadogRecorder-...'", also on a bare
  test page, in the shopper's headless Chromium 129. Not yet checked in a regular Chrome; if it
  works there, only synthetic sessions are affected.
