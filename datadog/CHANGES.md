# Changes from the upstream OpenTelemetry Demo

A running log of how this fork (matt-dog/opentelemetry-demo, branch
`datadog-demo`, `ddot-local-blog` until 2026-10-22) differs from upstream (open-telemetry/opentelemetry-demo), and
why. Newest first. The README tables describe the current state; this file keeps
the history. `ENVIRONMENT.md` records where it runs and what it depends on
outside this repo, for handover.

Nothing in the upstream source, images or Helm chart is modified. Every
difference is a new file under `datadog/`, or one of the few lines in
`.gitignore`, or an override passed to the upstream chart (0.42.1). Check with:

```bash
git diff --stat upstream/main...datadog-demo
```

Add an entry with every commit that changes the difference, and record changes
made by hand outside git under "Live changes not in git" until they are moved
into git or undone.

## Live changes not in git

| Date | Where | Change | Why | Status |
|---|---|---|---|---|
| 2026-10-22 | matt-dog org settings, Preferences (UI) | OTel Semantic Query Mode on | queries match OTel and Datadog metric names | on; an org setting, no API found to set it from git |
| 2026-10-18 | ddstaging log index `ddot-lab` (UI) | Filter widened to also match `env:otel-demo-gke-blog` app services | App logs fell through to `main`, which drops 99.99% | Redundant since `fc642ea5` (the env has its own index, first in order); can be reverted to `env:ddot-lab service:orders-*` |

## Log

### 2026-10-22 · Demo plan built: OTel names on metrics, DDOT SDK on fraud-detection, contrib Collector, stage cue
- **What:**
  - `DEMO-PLAN.md` (replaces `TOUR-PLAN.md`) and `DEMO-SCRIPT.md`, the presenter's walkthrough with links.
  - `kube-stack-values.yaml`: `metrics.resource_attributes_as_tags` on every collector's Datadog exporter.
  - `values-local.yaml`: fraud-detection runs the DDOT SDK (the swap already tried on `ad`).
  - `contrib-collector.yaml`: an upstream collector-contrib 0.161.0, Operator-managed, with the
    `postgresql`, `redis` and `kafka_metrics` receivers and the datadog extension.
  - `stage.sh`: start and stop `adHighCpu` on cue, with its change event, pausing the schedule.
  - `dd-apply.py`: an APM retention filter (`retention-filter.json`, `env:<env>` at 100%); monitors
    saved only when their definition changed. `ad-latency-threshold.json` now alerts at 20 ms.
  - `up.sh`: keys from the environment when set, else 1Password, read once each.
- **Why:**
  - Metric queries by OTel attribute names (`k8s.cluster.name`) found nothing: the exporter keeps
    only the Datadog names (`kube_cluster_name`) by default. That was the `N/A` cluster tag.
  - The DDOT Collector ships no PostgreSQL, Redis or Kafka metrics receivers (checked in the binary).
  - The org's default trace retention kept only a sample, so the slow GetAds traces were not
    searchable after 15 minutes.
  - The 50 ms monitor stayed OK through 25 minutes at about 100 ms p95. Every `dd-apply.py` run
    re-saved it, which restarts evaluation; and its warning band hid it. The 20 ms monitor alerted
    about a minute after creation.
  - 1Password prompts timed out mid-run.
- **Verified (API):** p95 3 to 6 ms baseline, about 100 ms within 2 minutes of `stage.sh start`; the
  slow trace's 4 logs by trace ID including "High CPU-Load problempattern enabled"; ad container at
  0.298 of a 0.3 CPU limit by OTel names; Host Profiler profiles for ad, PostgreSQL, Kafka, Envoy; a
  44-span checkout trace across 11 services, fraud-detection on the DDOT SDK, the same in Jaeger;
  PostgreSQL, Redis and Kafka metrics with OTel tags; RUM sessions. Not checked through the API:
  dashboards lighting up, the contrib row in Fleet Automation, the profile's function view.

### 2026-10-22 · kube-stack installer copied into the repo; old branch deleted
- **What:** the kube-stack installer `up.sh` runs is now `local/kube-stack/` (copied unchanged from
  DataDog/opentelemetry-examples at 4e131eb, the abandoned local branch
  `matthew-david/blog-jaeger-datadog`); `KUBE_STACK_DIR` defaults to it. The remote branch
  `ddot-local-blog` was deleted; every commit on it is in `datadog-demo`.
- **Why:** the demo depended on an unpushed branch on one laptop, so nobody else could run it.
  The enrichment learned on the old branch (one host name per node, `datadog.host.name` from
  `k8s.node.name`, Kubernetes tags on spans) is already in this branch's history and config.

### 2026-10-22 · Branch renamed `datadog-demo`; ENVIRONMENT.md for handover
- **What:** branch `ddot-local-blog` renamed `datadog-demo`. New `ENVIRONMENT.md`: the Datadog
  org, keys (as `op://` references), objects in the org, org settings and internal flags, the GKE
  cluster, and code outside this repo. Blog wording removed from `local/README.md`.
- **Why:** the demo is no longer for the DDOT launch blog. It is the general demo, to be handed
  over to demo engineering, so the environment is recorded next to the changes from upstream.

### 2026-10-22 · Local demo sends to the matt-dog org on datad0g.com
- **What:** `local/up.sh` defaults to `DD_SITE=datad0g.com` and reads its keys from
  `op://Employee/ddot-lab/matt-dog-dd-api-key` and `matt-dog-dd-app-key` (was ddstaging on datadoghq.com,
  `DD_API_KEY` and `DD_APP_KEY` fields). The GKE target is cluster `otel-demo`, env
  `otel-demo` (was `otel-demo-blog`, env `otel-demo-gke-blog`). It now checks the API key against the site before installing anything,
  and prints an `app.$DD_SITE` link. The RUM snippet's `site` comes from `DD_RUM_SITE` in the
  rum-config secret (was hardcoded `datadoghq.com`). `dd-apply.py` and `scenarios.yaml`
  default to datad0g.com. The Anthropic key stays on `ddot-lab`.
- **Why:** an org of Matthew's own gives full control over feature flags, monitors and
  indexes without sharing ddstaging with other teams. All of it can still point back at
  ddstaging by setting `DD_SITE`, `DD_API_KEY_REF` and `DD_APP_KEY_REF`.
- **dd-apply.py:** each object (log index, RUM application, each monitor) is applied on its own,
  so a key refused for one still applies the rest (was: the first refusal skipped everything).
  In matt-dog the log index is optional; `main` has no exclusion filter there. Creating it is
  refused (403) even with an unscoped app key, so the index is skipped there for now.
- **Cluster:** `otel-demo-blog` (ddstaging) and the old Home-tab `otel-demo` (asleep) were deleted
  and `otel-demo` recreated from this branch. Data confirmed in matt-dog: logs and spans from every
  shop service, 963 active metrics, 6 hosts. RUM application and both monitors created there.

### 2026-10-19 · Monitors: 15-minute recovery; threshold monitor applied
- **What:** `ad-latency-anomaly.json` recovers after 15 minutes without out-of-band points
  (`recovery_window: last_15m`, was 3). `ad-latency-threshold.json` applied (monitor 334131509).
- **Why:** with a 3-minute recovery the anomaly monitor went green about 5 minutes into the
  incident, because `basic` absorbs the new level, while latency was still high. It now stays red
  from about :33 to about :47, which matches the incident. The threshold monitor is red for the whole
  :30 to :45 window.

### 2026-10-19 · One host name per node
- **What:** `local/kube-stack-values.yaml` adds `resource/dd_hostname` to every Datadog pipeline of the
  daemon, cluster and host-profiler collectors: `datadog.host.name` from the item's `k8s.node.name`,
  else the collector's own node (`OTEL_K8S_NODE_NAME`). Both Datadog exporters send
  `kube_cluster_name`, `cluster_name` and `env` as host tags. `resource/hostname` is defined too,
  because the base's `null` for it survives `helm --reuse-values` and the collector rejects an empty
  processor (one daemon pod crash-looped on that before the fix). `up.sh` fills `__ENV_NAME__` into a
  temp copy of the overlay. Applied with `helm upgrade --reuse-values` on the kube-stack release.
- **Why:** each node showed as three hosts: `<node>` (the exporter's own host), `<node>.<project>`
  (Datadog's GCP rule: detector `host.name` plus `cloud.account.id`) and
  `<node>.c.<project>.internal` (the host profiler). Tags sat on one, metrics on another, so the host
  map's cluster filter and the profiling host filter came up empty. Datadog resolves
  `datadog.host.name` first (docs: opentelemetry/mapping/hostname). Verified 01:48Z: spans, node
  metrics and profiles report only the three bare node names; the old series stopped at 01:47:58Z.
- **Notes:** the shop's browser spans (`frontend-web`) now have no host, which is right for spans
  from a browser. `git.repository.id` on spans doesn't come from the pipeline.

### 2026-10-18 · DDOT SDK on ad: traces work, logs don't yet; kept opt-in
- **What:** `local/ddot-sdk-ad.values.yaml` (not applied by `up.sh`): an init container copies the
  agent jar from `datadog/dd-otel-autoinstrumentation-java:1.67-preview`, `JAVA_TOOL_OPTIONS` points
  at it in place of the image's upstream OTel agent, plus `OTEL_TRACES_EXPORTER=otlp` and
  `DD_TRACE_OTEL_ENABLED`, `DD_LOGS_OTEL_ENABLED`, `DD_METRICS_OTEL_ENABLED` (the settings on the DDOT
  SDK swap slide). Also `local/datadog/monitors/ad-latency-threshold.json`, a p95 > 50 ms monitor
  that stays in alert for the whole :30 to :45 window (applied with the next `dd-apply.py` run).
- **Why:** slide 24's before and after. Ran 23:12 to 23:16Z and 23:19 to 23:22Z. Traces work:
  spans arrive with `telemetry.sdk.name: datadog`, version 1.67.1, the right env and Kubernetes
  tags (they were only slow to index; an earlier entry here said they never arrived, which was
  wrong). Logs don't: none of the pod's logs carried trace context and nothing came through its
  OTLP log export, which breaks trace-to-logs on slide 9. So `ad` runs the upstream agent until
  that is fixed. The tracer's telemetry and debugger also try `localhost:8126` (no Agent); harmless.
- **Also:** RUM's `traceparent` wins over the shop's OTel browser SDK on API calls (checked with a
  headless browser: `tracestate: dd=s:1;o:rum`), so RUM actions open their backend traces and the
  shop's own browser spans become separate traces.

### 2026-10-18 · RUM with the Datadog Browser SDK; the shopper asks the AI assistant
- **What:**
  - `local/datadog/rum-application.json`: the RUM application, created by `dd-apply.py`, which
    writes its id and client token to a mode-600 temp file (`RUM_OUT`). `up.sh` turns that into
    the `rum-config` secret and now runs `dd-apply.py` before the shop is installed.
  - `local/frontend-proxy/envoy.tmpl.yaml`: the demo image's Envoy template (3.1.0) mounted over
    it, plus a Lua filter that inserts the RUM Browser SDK (v7, CDN) after `<head>` on the shop's
    and the chatbot's pages. It asks for an uncompressed body on page paths only; API, assets,
    Jaeger, Grafana and the flag UI are skipped. RUM service `frontend-web` (the name the shop's
    browser spans already use), Session Replay at 100%, `allowedTracingUrls` on the shop's origin
    with the W3C `tracecontext` propagator.
  - `local/shopper.yaml`: after each checkout the shopper opens `/chatbot/` and asks one of three
    shopping questions.
- **Why:** RUM, Session Replay and the link from a user action to its OpenTelemetry backend trace,
  with no Agent; and one browser session that covers shopping and the AI assistant (chatbot, agent,
  Claude, shop services). The shop's source and images are unchanged.
- **Notes:** the shop's own OTel browser SDK also sets `traceparent` on the same requests; which
  one wins decides which trace a RUM resource links to. To check in the RUM UI.

### 2026-10-18 · Three scenarios, each flip a Datadog change event
- **What:** `local/scenarios.yaml` now runs three non-overlapping windows each hour, UTC:
  `paymentFailure` 25% from :00 to :10, `aiRunawayAgent` on from :15 to :25, `adHighCpu` from :30
  to :45. At every flip it posts a change event (`/api/v2/events`, category `change`) on the affected
  service. `up.sh` creates the `scenarios-env` ConfigMap (env, site) and the `scenarios-dd` secret
  (API key from 1Password).
- **Why:** one problem per act of the tour, each with a quiet baseline, and the cause shown next to
  the effect: change tracking lists the flag flip on the service and as a marker on its graphs.
  Verified 23:00:17Z (`paymentFailure 25% (payment)` in change tracking).
- **Notes:** `aiRunawayAgent` on asks for 20 tool calls per prompt, past the agent's graph limit
  of 25, so some prompts end in a recursion error.

### 2026-10-18 · Load generator prompts for the agent on Claude
- **What:** `local/load-generator/locustfile.py` is the demo image's own `locustfile.py`
  (3.1.0) mounted over it from the `load-generator-locustfile` ConfigMap (`up.sh` creates it). Two
  changes, marked `datadog/local` in the file: six shopping questions replace the three prompts the
  recorded responses covered, and `user_ask_agent` no longer carries `gen_ai.input.messages`.
- **Why:** with a real model the prompts can be anything, so they now exercise the shop's tools,
  mostly `get_ads`, which ties the ad service's scenarios to the AI assistant. The attribute made the
  load generator's span the root of every Agent Observability trace, so the app was named
  `load-generator`.

### 2026-10-18 · `fd008a09` · The shop's AI agent on Claude (Haiku 5.5)
- **What:** `local/values-local.yaml` replaces the agent's `llm.py` (mounted from a ConfigMap) with the
  same `ChatLLM` class on LangChain's Anthropic client, model `claude-haiku-5-5`, recorded responses
  off (`USE_VCR=False`). The pod installs `langchain-anthropic==1.7.2` at start (the newest that fits
  the image's `langchain-core` 1.6.3). `local/up.sh` creates the `agent-llm` secret from
  `op://Employee/ddot-lab/ANTHROPIC_API_KEY`. The upstream image is unchanged.
- **Why:** Agent Observability showed no tokens or cost (`skipped_tokens_missing`) because the
  recordings carry no usage. With Claude, spans show provider `anthropic`, real tokens and
  `cost_estimate_status:success`. The native client was chosen over an OpenAI-compatible endpoint so
  the provider is recorded as Anthropic. The `aiSlowResponse` flag still applies.
- **Notes:** each call shows as the LangChain step and as the Anthropic SDK's own OTel span
  (`com.anthropic.sdk.python`). The LLM app name comes out as `load-generator`, the trace's root
  service; to be set to the shop assistant. Verified 22:47Z.

### 2026-10-18 · Planned: re:Invent feature tour (`TOUR-PLAN.md`)
- **What:** the plan for the next changes: clean-ups that show in screenshots, the DDOT SDK on
  `ad` and `recommendation`, RUM with the Datadog Browser SDK, a real Claude model behind the agent,
  change events and stage mode, a presenter dashboard and SLO from git, and an optional Agent for the
  "full value" slides.
- **Why:** screenshots for the re:Invent deck and a 15-minute tour of Datadog on OpenTelemetry data
  with DDOT components only. Nothing in it is applied yet; each step gets its own entry when it is.

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
