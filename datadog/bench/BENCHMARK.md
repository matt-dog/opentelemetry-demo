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

### Campaign `c2` (DDOT arms)

Pending.

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
