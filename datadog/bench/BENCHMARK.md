# DDOT vs contrib: egress and CPU on the OTel Demo

How much less data does the DDOT Collector send to Datadog than the upstream
contrib Collector with the Datadog Exporter, for the same telemetry, and what does
that cost? This directory holds everything needed to rerun the measurement.

## What differs between the two (from source)

| | contrib 0.159.0 + datadog exporter | contrib 0.159.0 + otlp_http | DDOT 7.84.3 |
|---|---|---|---|
| Metrics | v2 series, zlib (serializer path, on by default; v3 disabled) [1] | OTLP protobuf, zstd level 3 (set in config) | v3 series, zstd level 3 [2] |
| Traces and RED metrics | gzip; APM stats from the datadog connector [3] | OTLP, zstd 3; RED metrics from the community span_metrics connector | zstd level 3; APM stats from the datadog connector [2] |
| Logs | gzip [3] | OTLP, zstd level 3 | zstd level 3 [2] |
| Upstream Collector core | 0.159.0 | 0.159.0 | 0.159.0 [4] |

DDOT turns on v3 only when the exporter uses its default endpoint for a known
Datadog site and no proxy is set, and it logs a warning when it does not [2].
Check that line in every run.

[1] [serializerexporter/serializer.go](https://github.com/DataDog/datadog-agent/blob/dbdf7e37527d/comp/otelcol/otlp/components/exporter/serializerexporter/serializer.go#L86-L95), the version contrib 0.159.0 pins
[2] [cmd/otel-agent/config/agent_config.go@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/cmd/otel-agent/config/agent_config.go)
[3] [datadogexporter/compression_test.go@v0.159.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.159.0/exporter/datadogexporter/compression_test.go), which enforces gzip for every signal on the exporter's native paths. Metrics go through the serializer path instead while the `metricexportserializerclient` gate is on (beta, so on by default), which is [1].
[4] [collector-contrib/impl/manifest.yaml@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/comp/otelcol/collector-contrib/impl/manifest.yaml)

## Design

```
 Astronomy Shop apps ──OTLP──> demo collector (DaemonSet, the tee)
                                   │  same traces, metrics, logs to every arm
       ┌──────────────┬────────────┼──────────────┬─────────────────┐
       ▼              ▼            ▼              ▼
   contrib          ddot        ddotv2       ddotdefault        each arm: 3 pods
 (node 1)         (node 2)     (node 3)       (node 4)          (traces, metrics, logs)
                                                    + contribotlp (node 5)
       └──────────────┴────── Datadog (staging) ─┴─────────────────┘
```

Five arms receive identical input at the same time, so load swings hit all of
them equally.

| Arm | Image | What it isolates |
|---|---|---|
| `contrib` | `otel/opentelemetry-collector-contrib:0.159.0` | Baseline: what OSS users run today |
| `ddot` | `datadog/ddot-collector:7.84.3`, standalone, converter off | Same pipeline as contrib, DDOT exporter defaults |
| `ddotv2` | as `ddot`, plus v2 series, zlib and gzip logs forced | Splits the gain for metrics and logs: `ddotv2` vs `ddot` is v3 + zstd, `contrib` vs `ddotv2` is everything else. Traces stay zstd here (no trace compression switch was found), so this arm says nothing about traces. |
| `ddotdefault` | `datadog/ddot-collector:7.84.3`, image defaults | What a customer gets out of the box |
| `contribotlp` | `otel/opentelemetry-collector-contrib:0.159.0`, `otlp_http` to Datadog's OTLP intake, zstd level 3 | The docs' Datadog-Exporter-free path: `otlp_http` plus the community `span_metrics` connector, with exporter-side byte batching (2 to 4 MB) as the docs set it. Own configs: `otlp-*.yaml` |

Held equal across arms:
- **Config:** the same file per signal (`traces.yaml`, `metrics.yaml`,
  `logs.yaml`) for every Datadog Exporter arm. `contribotlp` uses the OTLP path's
  own docs config (`otlp-*.yaml`), so its batching and RED-metric computation
  differ by design. It uses the docs' Datadog Exporter batch settings and a
  `resource` processor that sets the arm's `env` so Datadog keeps the arms apart.
- **Node:** one dedicated `n2-standard-4` per arm, tainted so nothing else
  schedules there. The demo's DaemonSet and the profiler run on every bench node
  alike.
- **Resources:** each pod requests 250m CPU and 256Mi, with limits of 2 CPU and
  2Gi.
- **Input:** cumulative metrics, as the apps emit them.

DDOT standalone gets `DD_HOSTNAME` set to the node name. Without a core Agent
to ask, 7.84.3 exits at startup when it has no hostname. Contrib detects the
same node name on its own.

Why "converter off": DDOT's config converter adds `infraattributes`,
`cumulativetodelta`, a self-telemetry scrape and the `datadog` extension to a
user's config. That is useful, but it is extra work and extra data that contrib
does not do. `ddot` turns it off (`DD_OTELCOLLECTOR_CONVERTER_FEATURES=none`)
for a like-for-like comparison. `ddotdefault` keeps it, to show the
out-of-the-box number.

Why one pod per signal: pod network counters then split egress by signal, and
v3 only changes metrics.

## Measurements

- **Egress:** each benchmark pod's network tx bytes from the kubelet
  (`stats/summary`). These pods send only to Datadog. Their tx also carries TCP
  ACKs for the OTLP they receive. Inbound is identical across arms, so the ACKs
  are the same for every arm. `report.py` estimates them and subtracts them.
- **Items:** each collector's own `otelcol_receiver_accepted_*` counters, used to
  get bytes per span, per data point and per log record. Send failures are
  flagged.
- **CPU and memory:** kubelet core-seconds over the window, plus working set at
  the end. Peak memory is in Datadog (`kubernetes.memory.*` by `pod_name:bench-*`).
- **Full Host Profiler:** eBPF CPU profiles of every process on the bench nodes
  (`profiler-values.yml`, Profiling in Datadog, `env:bench-profiler`). These
  show where each collector spends its CPU: compression, serialization,
  batching.
- **Dollars:** projected GB/day times an internet egress list price, cited with
  its date (`report.py --usd-per-gb`). Each cloud's tiers differ, so the report
  shows the price used. For the headline, scale the per-item ratio to a round
  volume, in the style of the logs zstd announcement: savings per 10 TB/day of
  contrib egress at the cited price, counting internet egress only (no NAT or
  inter-zone charges unless stated).

## Protocol

1. `bench/up.sh`: demo + tee + four arms + profiler, `LOCUST_USERS=200`.
2. Check, during warmup (each step restarts pods, so do it before `start`):
   - every pod is Ready, and Datadog shows four envs with matching span counts;
   - `kubectl -n otel-demo logs deploy/bench-ddot-metrics | grep -i "v3 series"`
     is empty. DDOT prints a warning only when it wanted v3 and a guard blocked
     it. `ddotv2` prints nothing either, because it never asks for v3;
   - set `DD_LOG_LEVEL=debug` on the `ddot`, `ddotv2` and `ddotdefault` metrics
     and logs pods for a few minutes (`kubectl set env deploy/<name>
     DD_LOG_LEVEL=debug`). Record the series endpoint (v3 or v2) and the encoding
     each one uses. Confirm `infraattributes` and the datadog extension appear in
     `ddotdefault`'s startup output and not in `ddot`'s. Save the excerpts in
     `results/verification/`, then unset the variable.
3. Warm up for 30 minutes, then `python3 -I bench/measure.py run1 start`.
4. Steady state for 2 hours, then `python3 -I bench/measure.py run1 end`.
5. `python3 -I bench/report.py bench/results/run1 --usd-per-gb <price>`.
6. Repeat as `run2`. Then `LOCUST_USERS=400 bench/up.sh`, wait 30 minutes, and
   run as `run3-heavy`.
7. Optional, if time allows: raise the batch settings in all three configs (for
   example `send_batch_size: 1000`, `send_batch_max_size: 2000`), rerun
   `bench/up.sh`, and run as `run4-batch` to see whether the ratio holds.
8. `down.sh`, which sleeps the bench pool too.

## Caveats to state with any number

- The Astronomy Shop is one workload, driven by Locust HTTP users only (browser
  users are off: headless Chromium does not fit at 200 users). Ratios depend on payload shape: tag
  cardinality, log size, span attributes.
- Staging intake, not production. Payload encoding is the same; network paths
  differ.
- Docs-default batch settings. Larger batches compress better for every arm.
- The profiler adds CPU overhead to every arm alike. CPU numbers are with the
  profiler on.
- DDOT `ddotdefault` sends extra data (fleet metadata, self-telemetry) by
  design. That shows up as egress.

## Status

- 2026-10-15: cluster up on GKE (`us-east1-b`), sending to the ddstaging org.
  First deploy: contrib arms healthy; DDOT arms crashed for want of a hostname
  (fixed with `DD_HOSTNAME`); the profiler's system-probe container failed on
  COS (fixed with `providers.gke.cos`). `contribotlp` added. No numbers yet.

## Results

Each run's `start.json`, `end.json` and `report.md` land in `results/<run>/`.
