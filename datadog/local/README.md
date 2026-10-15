# Astronomy Shop on the OTel Operator and kube-stack, with the DDOT Collector

For the DDOT launch blog's screenshots: the familiar OpenTelemetry Demo, collected
by the DDOT Collector that the opentelemetry-examples kube-stack installer runs
(OTel Operator + kube-stack, ddot flow). The shop keeps its own Jaeger and Grafana;
Datadog gets everything. Runs on Rancher Desktop.

```
 Astronomy Shop services ──OTLP──> kube-stack DDOT daemon collector
   (upstream OTel SDKs)              (Operator-managed, ddot flow)
                                       ├─> Jaeger      (every trace)
                                       ├─> Prometheus  (metrics, span metrics: Grafana)
                                       └─> Datadog     (traces, metrics, logs)
```

## Run it

Needs about 12 GB for the VM (`rdctl set --virtual-machine.memory-in-gb 16
--virtual-machine.number-cpus 6`), `op` signed in, Helm, and
`~/code/opentelemetry-examples` checked out on a branch with the kube-stack
installer (`KUBE_STACK_DIR` overrides the path).

```bash
datadog/local/up-local.sh
kubectl --context rancher-desktop -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

- Shop: http://localhost:8080, flags at http://localhost:8080/feature
- Jaeger: http://localhost:8080/jaeger/ui
- Grafana: http://localhost:8080/grafana
- Datadog: APM, `env:otel-demo-local`

## Files

- `kube-stack-values.yaml`: overlay for the kube-stack installer. The daemon
  collector also exports traces to the shop's Jaeger, and metrics plus span
  metrics to its Prometheus, and accepts browser OTLP (CORS).
- `values-local.yaml`: the demo chart with its bundled Collector off and
  `OTEL_COLLECTOR_NAME` pointing every service at the kube-stack collector.
- `up-local.sh`: runs the installer (with a kubeconfig holding only the local
  context), then the demo chart.

## Notes

- Traces come from the shop's upstream OpenTelemetry SDKs through the DDOT
  Collector. The Operator does not inject the DDOT SDK here: the shop's images
  already carry OTel SDKs, and injecting would instrument them twice.
- The collector image is the one the kube-stack ddot flow pins (a DDOT dev build
  at the time of writing), not a released DDOT Collector.
- Swapping the demo chart's own Collector for the released DDOT Collector 7.84.3
  (tried first, 2026-10-15) took more than two lines: an empty `command.name`
  (the chart runs `/otelcol-contrib`), no `service.profilesSupport` gate,
  `DD_HOSTNAME`, and a new config, because the demo's uses five components DDOT
  7.84.3 does not ship (`kafkametrics`, `redaction`, `gen_ai_normalizer`,
  `opensearch`, `opamp`) plus a profiles pipeline.
