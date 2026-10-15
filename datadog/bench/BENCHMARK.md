# DDOT vs contrib: egress on the OTel Demo

How many bytes does the DDOT Collector send to Datadog, per span, data point and
log record, compared with the upstream contrib Collector and the Datadog
Exporter, given the same input?

Scope is egress bytes. CPU, memory and throughput are left to SMP, which runs on
quieter hardware than GKE.

## What differs (from source)

| | contrib 0.159.0 + datadog exporter | DDOT 7.84.3 |
|---|---|---|
| Metrics | v2 series, zlib [1] | v3 series, zstd 3 [2] |
| Traces, APM stats | gzip [3] | zstd 3 [2] |
| Logs | gzip [3] | zstd 3 [2] |
| Collector core | 0.159.0 | 0.159.0 [4] |

DDOT uses v3 only on the default endpoint of a known site with no proxy, and
logs a warning otherwise [2].

DDOT's config converter adds `infraattributes, prometheus, pprof, zpages,
health_check, ddflare, datadog, cumulativetodelta` to a user's config unless
`DD_OTELCOLLECTOR_CONVERTER_FEATURES` says otherwise [5].

[1] [serializer.go](https://github.com/DataDog/datadog-agent/blob/dbdf7e37527d/comp/otelcol/otlp/components/exporter/serializerexporter/serializer.go#L86-L95), as pinned by contrib 0.159.0
[2] [agent_config.go@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/cmd/otel-agent/config/agent_config.go)
[3] [compression_test.go@v0.159.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.159.0/exporter/datadogexporter/compression_test.go). Metrics take the serializer path [1] while the `metricexportserializerclient` gate is on (beta, default on).
[4] [manifest.yaml@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/comp/otelcol/collector-contrib/impl/manifest.yaml)
[5] [autoconfigure.go@7.84.3](https://github.com/DataDog/datadog-agent/blob/7.84.3/comp/otelcol/converter/impl/autoconfigure.go#L38)

## Design

The demo's collector is a tee: it sends identical enriched OTLP to every arm at
once. Each arm runs one pod per signal on its own tainted `n2-standard-4`.

| Arm | What it is |
|---|---|
| `contrib` | contrib 0.159.0 + Datadog Exporter. Baseline. |
| `ddot` | DDOT 7.84.3 standalone, converter off (`none`): same pipeline as contrib |
| `ddotv2` | `ddot` with v2 series, zlib and gzip logs forced. `ddot` vs `ddotv2` is v3 + zstd on metrics and logs. Traces stay zstd. |
| `ddotdefault` | DDOT at image defaults, converter on |
| `contribotlpeq` | reference: contrib + `otlp_http` (zstd 3) + `span_metrics`, same batching as above |
| `contribotlp` | reference: as `contribotlpeq` with the docs' 2 to 4 MB exporter batching |

The OTLP arms are a reference only. They hand format conversion and APM stats
to the intake, so the collector does less work and sends a different payload.
They are comparable on bytes only once Datadog shows the same data from them
(see Parity).

Every arm also runs an idle twin: the same image and config on the same node,
with no input. Its egress is the arm's fixed traffic outside the pipeline
(metadata, self-telemetry).

Held equal: input (the tee), enrichment (done once in the tee), config file per
signal for the Datadog Exporter arms (`traces.yaml`, `metrics.yaml`,
`logs.yaml`), batching (8192 items, 10s; except `contribotlp`), node shape,
resources (250m/256Mi requests, 2 CPU/2Gi limits), and a fixed-length
`host.name` suffix per arm so envs stay apart. DDOT gets `DD_HOSTNAME` from the
node name, which contrib detects on its own.

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
   metric series and points, APM stats present.
4. `down.sh`.

## Caveats

- One workload (Astronomy Shop, Locust HTTP users). Ratios depend on payload
  shape.
- Batch size moves every number. Quote the batching.
- `ddotdefault`'s `infraattributes` has no kubelet or `/host/proc` access here,
  so it adds fewer tags than a full deployment.

## Results

### Earlier runs (2026-10-15, preliminary)

Two short windows: run 1 (37 min, docs batching), run 2 (19 min, equal
batching). Run 2, bytes per item vs `contrib` (per-span, per-point and per-record columns; the last column is total bytes):

| Arm | Traces | Metrics | Logs | All signals |
|---|---:|---:|---:|---:|
| ddot | -26.8% | -58.9% | -18.0% | -29.4% |
| ddotv2 | -26.9% | +3.8% | +2.5% | -18.8% |
| ddotdefault | -26.5% | -59.3% | -17.5% | -29.2% |
| contribotlpeq (reference) | -79.6% | -33.7% | -52.1% | -69.9% |

`ddot` metrics moved from -4.7% in run 1 to -58.9% in run 2, so these need the
longer, repeated runs before any number is quoted.

### Campaign `c1`

Pending.
