# Environment

Where the demo runs and everything it depends on outside this repo, so it can be
handed over. `local/README.md` covers what differs from the upstream demo and how
to run it; `CHANGES.md` is the dated history, including hand changes not yet in git.
Keep this file current in the same commit as any change to the environment.

As of 2026-11-17.

## Datadog org

| | |
|---|---|
| Org | `DDOT Minus Reinvent26` (UUID `123517f4-cc63-11f1-8f7d-920bb8d70cfd`) |
| Site | `datadoghq.com`, UI at https://app.datadoghq.com |
| Env tag | `otel-demo` (GKE), `otel-demo-local` (Rancher Desktop) |
| API key | `op://Employee/ddot-lab/ddot-minus-api-key` |
| Application key | `op://Employee/ddot-lab/ddot-minus-app-key` (owner Matthew, Datadog Admin Role) |

DDOT Minus Reinvent26 is a shared org (another env there: `reinvent-otel-26-ddot-minus`).
Since 2026-11-17. From 2026-10-22 to 2026-11-17 the demo sent to Matthew's own org
`matt-dog` on datad0g.com (since renamed; UUID `799a88c5-cdb1-11f1-a32b-a2e4bbf2e8d2`,
keys `op://Employee/ddot-lab/matt-dog-dd-*`), and before that to the ddstaging org on
datadoghq.com (env `otel-demo-gke-blog`). `up.sh` goes to any of them with `DD_SITE`,
`DD_API_KEY_REF` and `DD_APP_KEY_REF` set. The matt-dog objects were left in place; its monitors are muted by downtime `0e2ce626-adac-4458-bc6d-7d4d02c6b536` (2026-11-17, no end).

### Objects in the org

Built from git by `local/dd-apply.py` (run by `up.sh`), matched by name, tagged
`managed_by:otel-demo-local` (dashboards: `team:otel-demo`):

| Object | Id | Status |
|---|---|---|
| RUM application `astronomy-shop (otel-demo)` | `ff1ba9cb-c19e-4918-a201-5caa40b12423` | created 2026-11-17 |
| Monitor `[otel demo] ad service latency anomaly (otel-demo)` | 346227643 | created 2026-11-17; needs about a day of history before its baseline is trustworthy |
| Monitor `[otel demo] ad service p95 latency high (otel-demo)` (per-minute p95 over 20 ms) | 346227650 | created 2026-11-17; Act 1's alert |
| Monitor `[otel demo] ad service error rate (otel-demo)` (errors over hits above 5%, 10 min) | 346227635 | created 2026-11-17 |
| Monitor `[otel demo] ad pod at its CPU limit (otel-demo)` (over 90% for 3 min, by `pod_name`) | 346227652 | created 2026-11-17; starts the remediate workflow |
| Monitor `[otel demo] product-catalog error rate (otel-demo)` (over 5%, 10 min) | 346227657 | created 2026-11-17; in Alert all the time by design (baseline productCatalogFailure) |
| Workflow `[otel demo] remediate ad latency (otel-demo)`, handle `@workflow-otel-demo-remediate-ad` | `a0e164c5-23db-4318-9f6c-991b07d45d1a` | created 2026-11-17 by `up.sh gke`; started by the ad pod CPU monitor; declares an incident (SEV-3, services: ad) only if none is open, waits 6 min, rolls back adHighCpu |
| HTTP connection `otel-demo remediator` (token auth) | created 2026-11-17 by `up.sh gke` | holds the remediator token |
| Workflow `[otel demo] resolve ad incident (otel-demo)`, handle `@workflow-otel-demo-resolve-ad-incident` | `7147c6e8-249c-4e40-9f09-0543ee9abc3d` | created 2026-11-17; not mentioned by any monitor |
| SLO `[otel demo] ad GetAds p95 under 20 ms (otel-demo)` | `b89fc7f6e91b543286617f3645818d73` | created 2026-11-17 |
| SLO `[otel demo] ad availability (otel-demo)` | `9b75c4bbef805a498df4a707279136bb` | created 2026-11-17 |
| Dashboard `[otel demo] the :30 to :45 window (otel-demo)` | `zcp-ds9-yyx` | created 2026-11-17; the Doc's Setup table still links the matt-dog one |
| Dashboard `[otel demo] ad CPU: profiler vs container (otel-demo)` | `6xe-m9q-5yg` | created 2026-11-17 |
| APM retention filter `otel demo: every span (otel-demo)` | `env:otel-demo` at 100% | created 2026-11-17 |
| Log index for the env | none | creation refused (403); not needed, since `main` has no exclusion filter in this org |

### Presenter script

The working script, with screenshots, is the Google Doc [OpenTelemetry Demo for Re:Invent 2026 and Beyond](https://docs.google.com/document/d/1wPKNAjw9LtjwA8UE87sPxdeEPcX8PrjnOWhUorht6MU/edit) (Matthew's; Step | Talking points table modeled on the Datadog 101 demo script). `DEMO-SCRIPT.md` is the earlier repo version; the Doc wins where they differ.

### Org settings and internal flags

Set by hand, outside git. Record each one here and under "Live changes not in git"
in `CHANGES.md` when it is turned on.

| Setting | Where | Status |
|---|---|---|
| OTel Semantic Query Mode | Organization Settings, Preferences | not checked in DDOT Minus Reinvent26 (was on in matt-dog since 2026-10-22) |
| `graphing_semantic_metric_names` (metrics features for OTel names) | Mosaic feature flag for the org | not checked in DDOT Minus Reinvent26 (was on in matt-dog since 2026-10-23) |
| `rum_otel_q4_25` (RUM UI for OTel browser data) | Mosaic feature flag, targeting rule v9 (Bill Meyer, approved by Pablo) | on in DDOT Minus Reinvent26 since 2026-11-18 17:01Z, per Slack; not checked in Mosaic |

## Kubernetes

| | |
|---|---|
| GKE cluster | `otel-demo`, project `dd-dev-otelpmdev`, zone `us-east1-b` |
| Nodes | 3 x `e2-standard-4`, network `ddot-lab`, subnet `ddot-lab-us-east1`, label `purpose=otel-demo` |
| Namespace | `otel-demo` |
| GKE maintenance window | daily 06:00 to 10:00 UTC (set 2026-10-24, and by `up.sh gke`); GKE's automatic upgrades recreate every node, so they stay out of demo hours |
| astronomy-db grant | `GRANT MAINTAIN ON catalog.products TO astronomy_user`, appended by `up.sh` to the chart's `postgresql-init` configmap (needed by productCatalogLockContention; a helm upgrade outside `up.sh` reverts it) |
| Collectors | DDOT daemon (one per node), DDOT cluster, DDOT Host Profiler (one per node), all in `opentelemetry-operator-system`; upstream `contrib` (collector-contrib 0.161.0) in `otel-demo` |
| Remediator (Act 3) | `https://34-54-251-237.sslip.io`: GKE Ingress on the global static IP `otel-demo-remediator` (34.54.251.237), Google-managed certificate, Cloud Armor policy `otel-demo-remediator` (Datadog webhooks ranges only), token in secret `remediator-token` |
| Problem schedule | `scenarios` pod, every hour, UTC, all inside :30 to :45: adHighCpu :30, paymentFailure 25% :31, aiRunawayAgent :32, imageSlowLoad 5s :33 (each to :45), kafkaQueueProblems :35 to :41, emailMemoryLeak 10000x :38 to :44, productCatalogLockContention :42 to :45. cartFailure 10% and the productCatalogFailure rule are held all the time by the same pod (`baseline.json`), so they survive a flagd restart. `local/stage.sh` is for testing changes only |
| Local | Rancher Desktop, context `rancher-desktop`, about 12 GB for the VM |

Created 2026-10-22 by `up.sh gke`. It replaced `otel-demo-blog` (sent to ddstaging)
and an earlier `otel-demo` cluster from the `ddot-vs-contrib-bench` branch; both
were deleted that day.

## Code outside this repo

| Dependency | Where | Handover risk |
|---|---|---|
| Upstream demo Helm chart | `open-telemetry/opentelemetry-demo` 0.42.1 | none |
| kube-stack installer (OTel Operator + DDOT collectors) | copied into `local/kube-stack/` from `DataDog/opentelemetry-examples` (abandoned local branch `matthew-david/blog-jaeger-datadog`, 4e131eb) | none; the copy is in this repo |
| Collector image | the one the kube-stack ddot flow pins (a DDOT dev build) | not a released DDOT Collector |
| Frontend image | `src/frontend` from the draft PR open-telemetry/opentelemetry-demo#4329, built here and pushed to Artifact Registry `us-east1-docker.pkg.dev/dd-dev-otelpmdev/otel-demo/frontend` (repo created 2026-11-19; the nodes' default compute service account has `artifactregistry.reader` on it) | the PR is a draft; rebuild when it changes or merges, and drop `FRONTEND_IMAGE` once a released demo image has it |

## Tools on the machine that runs it

`op` (signed in), `gcloud` (signed in to `dd-dev-otelpmdev`), `kubectl`, `helm`,
`python3`, `curl`. The frontend image is built by `local/frontend-build.sh` with Cloud Build in
`dd-dev-otelpmdev` (native `linux/amd64`, `rsync` needed locally); a local build under amd64
emulation (Rancher Desktop, Apple silicon) segfaults in `next build`.
