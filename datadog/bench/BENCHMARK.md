# DDOT exporters: egress on the OTel Demo

DDOT is the upstream Collector (core 0.159.0) with Datadog components added. So
the fair question is which exporter path sends fewer bytes, with the
distribution held fixed: how many bytes per span, data point and log record does
DDOT send to Datadog with the Datadog Exporter on v2, on v3, and with
`otlp_http`, given the same input and the same config?

Scope is egress bytes. CPU, memory and throughput are left to SMP, which runs on
quieter hardware than GKE.

## What differs (from source)

| | Datadog Exporter, v2 (`ddotv2`) | Datadog Exporter, v3 (`ddot`) | `otlp_http` (`ddototlp`) |
|---|---|---|---|
| Metrics | v2 series, zlib | v3 series, zstd 3 [2] | OTLP, zstd 3 |
| Traces | Datadog format, zstd 3 | Datadog format, zstd 3 [2] | OTLP, zstd 3 |
| APM stats | datadog connector, sent by the collector | same | none sent; `span_metrics` sends RED metrics |
| Logs | gzip 6 | zstd 3 [2] | OTLP, zstd 3 |

`ddotv2` sends what contrib 0.159.0's Datadog Exporter sends, except traces:
contrib uses gzip for traces [3] and DDOT has no switch for that. Contrib cannot
send v3: its pinned serializer forces zlib and turns v3 off [1].

DDOT uses v3 only on the default endpoint of a known site with no proxy, and
logs a warning otherwise [2]. DDOT's config converter adds `infraattributes,
prometheus, pprof, zpages, health_check, ddflare, datadog, cumulativetodelta`
unless `DD_OTELCOLLECTOR_CONVERTER_FEATURES` says otherwise [4]. It is off
(`none`) on every arm.

[1] [serializer.go:88-93](https://github.com/DataDog/datadog-agent/blob/dbdf7e37527d/comp/otelcol/otlp/components/exporter/serializerexporter/serializer.go#L88-L93), as pinned by contrib 0.159.0
[2] [agent_config.go@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/cmd/otel-agent/config/agent_config.go)
[3] [compression_test.go@v0.159.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.159.0/exporter/datadogexporter/compression_test.go)
[4] [autoconfigure.go@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/comp/otelcol/converter/impl/autoconfigure.go#L38)

## Design

The demo's collector is a tee: it sends identical enriched OTLP to every arm at
once. Each arm runs one pod per signal on its own tainted `n2-standard-4`, all
on `datadog/ddot-collector:7.84.3`.

| Arm | Config |
|---|---|
| `ddotv2` (baseline) | `traces.yaml`, `metrics.yaml`, `logs.yaml`; v2, zlib and gzip logs forced by env |
| `ddot` | same files, DDOT defaults (v3, zstd) |
| `ddototlp` | `otlp-*.yaml`: same receiver, processors and batching, `otlp_http` exporter, `span_metrics` in place of the datadog connector, `cumulativetodelta` on metrics (the Datadog Exporter does that conversion itself) |

Every arm also runs an idle twin: the same image and config on the same node,
with no input. Its egress is the arm's fixed traffic outside the pipeline.

Held equal: image, input, enrichment (done once in the tee), batching (8192
items, 10s), node shape, resources (250m/256Mi requests, 2 CPU/2Gi limits),
`DD_HOSTNAME` from the node name, and a fixed-length `host.name` suffix per arm.

`ddototlp` hands format conversion and APM stats to the intake. Its bytes compare
fairly only once Datadog shows the same data from it (Parity, below).

## Measurement

- **Egress:** pod tx bytes from the kubelet, minus estimated ACKs for the
  inbound OTLP (same for every arm).
- **Per item:** divided by what the tee sent that arm. The arm's own receiver
  count is a cross-check; a mismatch over 1% is flagged.
- **Fixed egress:** idle twin tx, as a share of the loaded arm's.
- **Stability:** 3 windows of 90 minutes, arms rotated across nodes between
  windows, a snapshot at each midpoint to compare halves.

## Protocol

1. `PROFILER=0 bench/up.sh` (`LOCUST_USERS=200`).
2. `bench/campaign.sh <name>`: debug logs on the DDOT metrics and logs pods
   (saved to `results/<name>-verification/`), 30 min warmup, then 3 windows with
   `rotate.sh` and 15 min rewarm between them. Reports land in
   `results/<name>-r<n>/`.
3. Parity, per env in Datadog over each window: ingested spans, log count,
   metric series and points, APM stats or trace metrics present.
4. `down.sh`.

## Caveats

- One workload (Astronomy Shop, Locust HTTP users). Ratios depend on payload
  shape.
- Batch size moves every number. Quote the batching.

## Results

### Campaign `c2` (DDOT arms), 2026-10-16

Two windows, arms on different nodes in each: `r1` 10:38 to 12:09 ET (1.5 h),
`r2` 12:24 to 16:04 ET (3.7 h). Window 3 did not run (the runner was stopped);
`r2` was closed by hand with its pods untouched since the rotation. 200 Locust
users, 8192-item batches. No input warnings.

Bytes per item in `r2`, and change vs `ddotv2`:

| Arm | Traces (B/span) | Metrics (B/point) | Logs (B/record) | All signals (total bytes) |
|---|---:|---:|---:|---:|
| `ddotv2` (Datadog Exporter, v2) | 198.8 | 27.0 | 172.6 | 14.7 GB/day |
| `ddot` (Datadog Exporter, v3) | 198.9 (+0.1%) | 10.5 (-61.0%) | 141.9 (-17.8%) | -10.3% |
| `ddototlp` (`otlp_http`) | 55.6 (-72.0%) | 17.9 (-33.8%) | 79.3 (-54.1%) | -64.3% |

Every change vs `ddotv2` was within 1 point across all four half-windows (`r1`
all signals: `ddot` -10.2%, `ddototlp` -64.5%).

- Traces: v2 and v3 are identical; v3 changes metrics only. The OTLP gap on
  traces is format, since both compress with zstd 3.
- Metrics: v3 is the smallest of the three.
- Fixed egress (idle twins): 0.2% or less of each arm's loaded egress.
- Parity, `r1` first half (10:38 to 11:24): ingested spans and log events per
  env within 0.7% of what the tee sent, for all three arms. Trace metrics
  (`trace.http.server.request.hits`, `trace.grpc.server.request.hits`) present
  for `ddototlp` and within 0.7% of the Datadog Exporter arms.
- Metrics parity, `r2`: identical across all three envs for converted types
  (`http.server.request.duration` and `rpc.server.duration` counts,
  `demo.payment.transactions`) and for UpDownCounters, which `cumulativetodelta`
  leaves cumulative (`jvm.thread.count`, `http.server.active_requests`). The OTLP
  intake drops cumulative metrics, so delta conversion is required; `ddototlp`
  has run `cumulativetodelta` since the first commit, and nothing was missing.

### Against contrib (campaign `c1`, 2026-10-15)

`c1` ran contrib beside DDOT. It was stopped after 45 minutes of its first
window to switch to the design above. Bytes per item vs contrib 0.159.0 + Datadog
Exporter, 21:18 to 22:04 ET:

| Arm | Traces | Metrics | Logs | All signals (total bytes) |
|---|---:|---:|---:|---:|
| ddot | -23.5% | -58.8% | -16.3% | -27.0% |
| ddotv2 | -23.7% | +3.2% | +2.2% | -16.2% |
| ddotdefault (converter on) | -23.4% | -59.8% | -16.5% | -27.0% |
| contrib + `otlp_http` | -78.9% | -33.1% | -51.6% | -68.8% |

Verified at runtime: logs zstd 3 on `ddot` and `ddotdefault`, gzip 6 on
`ddotv2`; metrics v3 series on `ddot`, v2 on `ddotv2`. Idle twins: fixed egress
was 0.08% of `ddot`'s loaded egress and 0.24% of `ddotdefault`'s.

Runs 1 and 2 (37 and 19 minutes, earlier the same day) are superseded.
