#!/usr/bin/env python3
"""Snapshot the benchmark collectors' counters. See BENCHMARK.md.

    python3 -I bench/measure.py <run> <phase>     e.g.  run1 start, run1 end

Writes bench/results/<run>/<phase>.json with, for every benchmark pod and idle twin:
  - kubelet stats/summary: pod network rx/tx bytes, CPU core-seconds, working set
  - the collector's own telemetry on :8888: items received and sent per signal
  - the tee's per-exporter sent and failed counts, to prove every arm got the same input

All counters are cumulative since pod start; report.py subtracts start from end.
A restart resets them, so the pod uid and restart count are recorded too.
"""
import json
import pathlib
import re
import subprocess
import sys
import time

NS = "otel-demo"
HERE = pathlib.Path(__file__).resolve().parent

# Collector self-telemetry counters worth keeping (Prometheus names).
COUNTERS = re.compile(
    r"^(otelcol_(receiver_accepted|receiver_refused|exporter_sent|exporter_send_failed)"
    r"_(spans|metric_points|log_records)|otelcol_process_cpu_seconds)(_total)?\b"
)


def kubectl(*args):
    return subprocess.run(["kubectl", "-n", NS, *args], check=True,
                          capture_output=True, text=True).stdout


def telemetry(pod):
    """Sum each kept counter across its label sets."""
    try:
        text = kubectl("get", "--raw", f"/api/v1/namespaces/{NS}/pods/{pod}:8888/proxy/metrics")
    except subprocess.CalledProcessError as e:
        return {"error": e.stderr.strip()}
    out = {}
    for line in text.splitlines():
        m = COUNTERS.match(line)
        if m:
            name = m.group(1)
            out[name] = out.get(name, 0.0) + float(line.rsplit(" ", 1)[1])
    return out


TEE = re.compile(r'^otelcol_exporter_(sent|send_failed|enqueue_failed)_(spans|metric_points|log_records)(?:_total)?\{[^}]*exporter="(otlp_grpc/bench-[^"]+)"[^}]*\} (\S+)')


def tee_counters(pod):
    try:
        text = kubectl("get", "--raw", f"/api/v1/namespaces/{NS}/pods/{pod}:8888/proxy/metrics")
    except subprocess.CalledProcessError:
        return {}
    out = {}
    for line in text.splitlines():
        m = TEE.match(line)
        if m:
            key = f"{m.group(3)} {m.group(1)}_{m.group(2)}"
            out[key] = out.get(key, 0.0) + float(m.group(4))
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    run, phase = sys.argv[1], sys.argv[2]
    pods = json.loads(kubectl("get", "pods", "-l", "app in (bench,bench-idle)", "-o", "json"))["items"]
    summaries = {}
    snap = {"taken": time.time(), "taken_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "pods": {}}
    for p in pods:
        meta, spec = p["metadata"], p["spec"]
        node = spec.get("nodeName")
        if node and node not in summaries:
            summaries[node] = json.loads(kubectl("get", "--raw", f"/api/v1/nodes/{node}/proxy/stats/summary"))
        stats = next((s for s in summaries.get(node, {}).get("pods", [])
                      if s["podRef"]["name"] == meta["name"]), {})
        net = stats.get("network", {})
        cstats = next(iter(stats.get("containers", [])), {})
        cs = next(iter(p["status"].get("containerStatuses", [])), {})
        snap["pods"][meta["name"]] = {
            "arm": meta["labels"]["bench-arm"],
            "idle": meta["labels"]["app"] == "bench-idle",
            "signal": meta["labels"]["bench-signal"],
            "uid": meta["uid"],
            "node": node,
            "image": cs.get("image"),
            "restarts": cs.get("restartCount"),
            "rx_bytes": net.get("rxBytes"),
            "tx_bytes": net.get("txBytes"),
            "cpu_core_ns": cstats.get("cpu", {}).get("usageCoreNanoSeconds"),
            "mem_working_set": cstats.get("memory", {}).get("workingSetBytes"),
            "telemetry": telemetry(meta["name"]),
        }
    # The tee's per-exporter counters, summed over its DaemonSet pods. A send
    # failure or queue drop here means that arm got less input than the others.
    tee = {}
    for p in json.loads(kubectl("get", "pods", "-l", "component=agent-collector", "-o", "json"))["items"]:
        for key, val in tee_counters(p["metadata"]["name"]).items():
            tee[key] = tee.get(key, 0.0) + val
    snap["tee"] = tee

    out = HERE / "results" / run / f"{phase}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(snap, indent=2, sort_keys=True))
    print(f"{len(snap['pods'])} pods -> {out}")


if __name__ == "__main__":
    main()
