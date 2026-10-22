# kube-stack installer (copied)

The installer `up.sh` runs to put the OpenTelemetry Operator and the DDOT
collectors (kube-stack, ddot flow) on the cluster. Copied unchanged on 2026-10-22 from
`DataDog/opentelemetry-examples`, path
`guides/kubernetes/configuration/opentelemetry-kube-stack`, branch
`matthew-david/blog-jaeger-datadog` at `4e131ebe`. That branch was never pushed and
is abandoned; this copy is the only one the demo uses.

Only the files `install` reads are here: `install`, `uninstall`, `values-ddot.yaml`,
`values-otlp-http.yaml`, `dd-agent-values.yaml` and the three `host-profiler-*` files.
The branch added three things over that repo's main (`d46456cc`):

- the Datadog Agent is optional in the ddot flow (`DD_AGENT_ENABLED=false`, which `up.sh` sets)
- namespaces can be auto-instrumented from the installer
- a Jaeger overlay for a screenshot (its `blog-jaeger/` folder is not copied; the shop's own
  Jaeger is fed by `../kube-stack-values.yaml` instead)

Edit these files here, with a `CHANGES.md` entry. `KUBE_STACK_DIR` still points
`up.sh` at another copy if needed.
