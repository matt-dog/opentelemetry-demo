# Verification, 2026-10-15 (raw startup logs kept locally in results/verification/, not committed: they carry the masked key suffix)

| Arm | Metrics endpoint | Trace compression | Converter | Notes |
|---|---|---|---|---|
| ddot | `/api/intake/metrics/v3/series` (202) | zstd | off: no infraattributes, ddflare or datadog extension in the logs | no errors, no v3 warning |
| ddotv2 | `/api/v2/series` (202) | zstd | off | v3 off as intended; traces still zstd, so this arm isolates metrics and logs only |
| ddotdefault | `/api/intake/metrics/v3/series` | zstd | on: `infraattributes/dd-autoconfigured`, ddflare present | infraattributes logs "Cannot get tags for entity: empty entity ID" for resources without a container. No kubelet or /host/proc access in this setup, so it adds fewer tags than a full deployment would |
| contrib | v2 series, zlib (from source) | gzip (from source) | n/a | |
| contribotlp | OTLP, zstd 3 (config) | zstd 3 (config) | n/a | |

Lines quoted from the logs:

    ddot      Successfully posted payload to "https://api.datadoghq.com/api/intake/metrics/v3/series" (202 Accepted)
    ddot      Trace writer initialized (climt=5 qsize=1 compression=zstd)
    ddotv2    Successfully posted payload to "https://api.datadoghq.com/api/v2/series" (202 Accepted)
    ddotv2    Trace writer initialized (climt=5 qsize=1 compression=zstd)

Not yet verified at runtime: logs compression per arm (zstd vs gzip). Needs
`DD_LOG_LEVEL=debug` on the logs pods during warmup.
