# re:Invent feature tour: plan

Status: proposed 2026-10-18, waiting on Matthew's go-ahead and the inputs at the end.
Every change made from this plan gets an entry in `CHANGES.md`.

## Goal

Screenshots for the re:Invent OpenTelemetry deck (outline in `/tmp/reinvent-otel-deck-outline.md`),
plus a 15-minute on-stage tour of how deep and broad Datadog goes on OpenTelemetry data. The
message: one cluster, DDOT components only, no Datadog Agent. One later section adds the Agent as an
optional enabler, for the "full value" slides (20 and 21).

## Decisions (2026-10-18)

- Org (since 2026-10-22): matt-dog on datad0g.com, env `otel-demo`; see `ENVIRONMENT.md`.
- Org (until 2026-10-22): ddstaging. Every link and query is scoped to `env:otel-demo-gke-blog`, because another team
  runs the same demo in the org.
- RUM: the Datadog Browser SDK, installed in the shop's frontend path.
- Components: DDOT Collector throughout, the DDOT SDK, and the DDOT Host Profiler.
- AI: a real Claude model behind the shop's agent, so tokens and cost show in Agent Observability.
- Slot: 15 minutes, not all live. Screenshots for slides come first.

## What already works with no Agent (verified 2026-10-18)

Kubernetes Explorer, host list (needs the fix below), APM with browser-started traces, logs linked to
traces, Error Tracking with code locations, the anomaly monitor, Host Profiler, Agent Observability
(LangGraph agent; no token counts yet), Kafka metrics, Jaeger and Grafana fed by the same pipeline.

## Work, in order

### 1. Clean-ups that show in screenshots
- Duplicate hosts: each node reports under three names (`<node>`, `<node>.dd-dev-otelpmdev`,
  `<node>.c.dd-dev-otelpmdev.internal`), 9 hosts for 3 nodes. Make every signal resolve to one host
  name.
- `git.repository.id` on spans (`datadog/datadog-agent-internal`, `datadog/test-repo-ad`): find where
  it is set and remove or correct it.
- Keep the internal project id out of host names, if possible.

### 2. DDOT SDK (slides 21, 24)
- `ad` (Java) and `recommendation` (Python) get the DDOT SDK through the OTel Operator
  `Instrumentation` resource (`datadog/dd-otel-autoinstrumentation-java:1.67-preview`,
  `datadog/dd-otel-autoinstrumentation-python:4.16-preview`), replacing the demo's own OTel agent.
- The values diff becomes slide 24's before and after.
- Check: spans still OTLP to the DDOT Collector, same service names, nothing lost in APM.

### 3. RUM with the Datadog Browser SDK (slide 10 or a new slide)
- A RUM application created from git by `dd-apply.py`. The client token is read from 1Password at
  apply time and kept out of git.
- The SDK is added in the frontend pod (a script tag through `frontend-proxy`, or a small frontend
  change; approach decided at build time and logged), with `allowedTracingUrls` using the W3C
  `tracecontext` propagator so a click links to its OTel backend trace. Session Replay on.
- Risk to test first: the shop's own OTel browser SDK also injects `traceparent`. Both on the same
  fetch may break the link.
- The Playwright shopper produces the sessions. Check that RUM keeps headless sessions.

### 4. A real Claude model behind the agent (slide 13)
- The agent uses LangChain's OpenAI client (`langchain_openai.ChatOpenAI`) with recorded responses
  (`USE_VCR`). Turning off the recordings and pointing it at Claude has two routes (inputs below).
- Limit cost: the load generator sends about 200 prompts an hour (about 400 model calls).

### 5. Stage mechanics
- Scenarios pod posts a Datadog change event at every flag flip ("adHighCpu on").
- Second scenario: `paymentFailure` at 25% from :00 to :10, for Error Tracking.
- Stage mode: a scenario starts a set number of minutes after a cue, from git.

### 6. From git through `dd-apply.py`
- A presenter dashboard: one graph per act, each grouped by `service`, `pod_name` or `host` so the
  graph menu opens the right pages.
- A checkout success SLO, and Service Catalog entries (owner, runbook, links).

### 7. Full value with the Agent (slides 20 and 21, after every no-Agent screenshot is taken)
- `up.sh gke --with-agent`: the Datadog Agent beside the DDOT components, as the optional enabler.
- Light up what slide 21 marks "Needs Agent" on the DDOT SDK services: Live Debugger and Dynamic
  Instrumentation on `ad`, plus Database Monitoring on the shop's Postgres and Data Streams on Kafka
  if they work with the DDOT SDK. Each one verified before it goes on a slide.
- Remove it again with one command, so the no-Agent tour stays true.

## Screenshot map

| Slide (outline) | Shot | From |
|---|---|---|
| 5 | What runs in the cluster | `kubectl get pods -A` (see conflict 1) |
| 7 | Same trace in Jaeger and Datadog | Today |
| 9 | Trace, logs, CPU, profile | Done |
| 10 | APM, host map, Kubernetes Explorer, Kafka dashboard, Agent Observability, Host Profiler | Today, plus 1 |
| 11 | Kubernetes Explorer | Today |
| 12 | APM service page | Today |
| 13 | Agent Observability with tokens and cost | 4 |
| 15, 16, 23 | Fleet Automation inventory, topology, config rollout | Check in the UI |
| 21 | DDOT SDK, Live Debugger, Dynamic Instrumentation | 2, 7 |
| 22 | Host Profiler flame graph | Today |
| 24 | Before and after YAML | 2 |
| new | RUM session linked to backend trace, Session Replay | 3 |

## The 15-minute tour

1. Nothing of ours but DDOT: the cluster, Kubernetes Explorer (2 min).
2. A shopper's session in RUM, the click, its backend trace (3 min).
3. Something breaks: event marker, alert, trace, logs, CPU limit, profile line (4 min).
4. The AI shopping agent on Claude: steps, tool calls, tokens, cost (3 min).
5. Running the pipeline: Fleet Automation (2 min).
6. The same trace in Jaeger, then the honest "needs the Agent" slide (1 min).

## Conflicts with the outline

1. Slide 5 says "Datadog software: None" on an upstream Collector. With DDOT throughout, the cluster
   runs Datadog components. Either slide 5 changes, or its screenshot comes from a short run on the
   contrib Collector.
2. Slide 15 wants `otelcol-contrib` and DDOT side by side in Fleet Automation. DDOT-only means no
   contrib row, unless one contrib Collector is kept for that shot.
3. DDOT standalone was unannounced as of September; check its public status before stage.
