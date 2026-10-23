# Environment

Where the demo runs and everything it depends on outside this repo, so it can be
handed over. `local/README.md` covers what differs from the upstream demo and how
to run it; `CHANGES.md` is the dated history, including hand changes not yet in git.
Keep this file current in the same commit as any change to the environment.

As of 2026-10-22.

## Datadog org

| | |
|---|---|
| Org | `matt-dog` (UUID `799a88c5-cdb1-11f1-a32b-a2e4bbf2e8d2`) |
| Site | `datad0g.com`, UI at https://app.datad0g.com |
| Env tag | `otel-demo` (GKE), `otel-demo-local` (Rancher Desktop) |
| API key | `op://Employee/ddot-lab/matt-dog-dd-api-key` |
| Application key | `op://Employee/ddot-lab/matt-dog-dd-app-key` (no scopes; owner Matthew, Datadog Admin Role) |
| Anthropic key (shop's agent) | `op://Employee/ddot-lab/ANTHROPIC_API_KEY` |

Until 2026-10-22 the demo sent to the ddstaging org on datadoghq.com (env
`otel-demo-gke-blog`). `up.sh` still goes there with `DD_SITE`, `DD_API_KEY_REF`
and `DD_APP_KEY_REF` set.

### Objects in the org

Built from git by `local/dd-apply.py` (run by `up.sh`), matched by name, tagged
`managed_by:otel-demo-local`:

| Object | Id | Status |
|---|---|---|
| RUM application `astronomy-shop (otel-demo)` | `8d3ef4e9-394d-4519-9cbe-aeee1a60d120` | created 2026-10-22 |
| Monitor `[otel demo] ad service latency anomaly (otel-demo)` | 35241062 | created 2026-10-22; needs about a day of history before its baseline is trustworthy |
| Monitor `[otel demo] ad service p95 latency high (otel-demo)` (per-minute p95 over 20 ms) | 35243022 | created 2026-10-22; Act 1's alert. Replaced the 50 ms monitor 35241065 (deleted), which stayed OK through the problem |
| APM retention filter `otel demo: every span (otel-demo)` | `env:otel-demo` at 100% | created 2026-10-22, so the demo's traces stay searchable after Live Search's 15 minutes |
| Log index for the env | none | creation refused (403) even with an unscoped key; not needed here, since `main` has no exclusion filter in this org |

### Org settings and internal flags

Set by hand, outside git. Record each one here and under "Live changes not in git"
in `CHANGES.md` when it is turned on.

| Setting | Where | Status |
|---|---|---|
| OTel Semantic Query Mode | Organization Settings, Preferences | on since 2026-10-22 (Matthew) |
| `graphing_semantic_metric_names` (metrics features for OTel names) | Mosaic feature flag for the org | on since 2026-10-23 (Matthew) |

## Kubernetes

| | |
|---|---|
| GKE cluster | `otel-demo`, project `dd-dev-otelpmdev`, zone `us-east1-b` |
| Nodes | 3 x `e2-standard-4`, network `ddot-lab`, subnet `ddot-lab-us-east1`, label `purpose=otel-demo` |
| Namespace | `otel-demo` |
| Collectors | DDOT daemon (one per node), DDOT cluster, DDOT Host Profiler (one per node), all in `opentelemetry-operator-system`; upstream `contrib` (collector-contrib 0.161.0) in `otel-demo` |
| Problem schedule | `scenarios` pod: paymentFailure :00 to :10, aiRunawayAgent :15 to :25, adHighCpu :30 to :45 each hour, UTC; `local/stage.sh` pauses it for a live demo |
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

## Tools on the machine that runs it

`op` (signed in), `gcloud` (signed in to `dd-dev-otelpmdev`), `kubectl`, `helm`,
`python3`, `curl`.
