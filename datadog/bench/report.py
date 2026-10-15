#!/usr/bin/env python3
"""Turn two measure.py snapshots into the comparison. See BENCHMARK.md.

    python3 -I bench/report.py bench/results/<run> [--usd-per-gb 0.09]

Reads start.json and end.json, prints a Markdown report and saves it as
report.md beside them. Every number is end minus start for the same pod.

Comparisons are per item (bytes per span, data point, log record), so an arm
that lost input cannot look better than it is. Input gaps over 1% are flagged.

Egress is the pod's network tx bytes. Each benchmark pod only sends to Datadog,
but its tx also carries TCP ACKs for the OTLP it receives from the tee. That is
the same for every arm (same input), and is estimated and shown separately: one
ACK of ~66 bytes per two ~1448-byte segments received.
"""
import argparse
import json
import pathlib
import sys

ACK_RATIO = 66 / (2 * 1448)
ITEMS = {"traces": "spans", "metrics": "metric_points", "logs": "log_records"}
BASELINE = "contrib"
ARM_ORDER = ["contrib", "contribotlp", "contribotlpeq", "ddot", "ddotv2", "ddotdefault"]
ARM_LABEL = {
    "contrib": "contrib 0.159.0 + datadog exporter",
    "contribotlp": "contrib 0.159.0 + otlp_http (zstd, docs batching)",
    "contribotlpeq": "contrib 0.159.0 + otlp_http (zstd, equal batching)",
    "ddot": "DDOT 7.84.3 standalone (converter off)",
    "ddotv2": "DDOT, v2 + zlib/gzip forced (converter off)",
    "ddotdefault": "DDOT 7.84.3 standalone (image defaults)",
}


def load(run, phase):
    return json.loads((run / f"{phase}.json").read_text())


def counter(p, name):
    t = p["telemetry"]
    return t.get(f"otelcol_{name}", 0.0) if "error" not in t else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=pathlib.Path)
    ap.add_argument("--usd-per-gb", type=float, default=None,
                    help="internet egress list price to convert bytes to dollars; cite its source")
    a = ap.parse_args()
    start, end = load(a.run, "start"), load(a.run, "end")
    secs = end["taken"] - start["taken"]

    rows, warnings = {}, []
    for name, e in end["pods"].items():
        s = start["pods"].get(name)
        if not s or s["uid"] != e["uid"] or s["restarts"] != e["restarts"]:
            warnings.append(f"{name}: restarted or replaced during the window; left out")
            continue
        sig = e["signal"]
        item = ITEMS[sig]
        recv = (counter(e, f"receiver_accepted_{item}") or 0) - (counter(s, f"receiver_accepted_{item}") or 0)
        failed = (counter(e, f"exporter_send_failed_{item}") or 0) - (counter(s, f"exporter_send_failed_{item}") or 0)
        refused = (counter(e, f"receiver_refused_{item}") or 0) - (counter(s, f"receiver_refused_{item}") or 0)
        rx = e["rx_bytes"] - s["rx_bytes"]
        tx = e["tx_bytes"] - s["tx_bytes"]
        ack = rx * ACK_RATIO
        rows[(e["arm"], sig)] = {
            "tx": tx, "rx": rx, "ack": ack, "net": tx - ack, "items": recv, "failed": failed, "refused": refused,
            "cores": (e["cpu_core_ns"] - s["cpu_core_ns"]) / 1e9 / secs,
            "mem": e["mem_working_set"],
        }
        if failed:
            warnings.append(f"{name}: {failed:.0f} {item} failed to send")
        if refused:
            warnings.append(f"{name}: refused {refused:.0f} {item} (memory_limiter)")

    # Every arm must get the same input, or bytes per item is the only fair
    # comparison and totals mislead. Flag gaps over 1% against contrib.
    for (arm, sig), r in rows.items():
        base = rows.get((BASELINE, sig))
        if base and base["items"] and abs(r["items"] / base["items"] - 1) > 0.01:
            warnings.append(f"bench-{arm}-{sig}: received {r['items']:,.0f} vs contrib's {base['items']:,.0f}")
    for key, val in end.get("tee", {}).items():
        if "failed" in key and val - start.get("tee", {}).get(key, 0.0) > 0:
            warnings.append(f"tee {key}: {val - start['tee'].get(key, 0.0):,.0f} during the window")

    out = []
    w = out.append
    w(f"# DDOT vs contrib egress: {a.run.name}\n")
    w(f"Window: {start['taken_iso']} to {end['taken_iso']} ({secs/3600:.2f} h).\n")
    if warnings:
        w("**Warnings**\n")
        w("\n".join(f"- {x}" for x in warnings) + "\n")

    for sig, item in ITEMS.items():
        base = rows.get((BASELINE, sig))
        w(f"## {sig}\n")
        w(f"| Arm | Items received | Egress MB | Est. ACK MB | Bytes per {item[:-1].replace('_', ' ')} | Per item vs contrib | CPU cores | Mem MiB |")
        w("|---|---:|---:|---:|---:|---:|---:|---:|")
        for arm in ARM_ORDER:
            r = rows.get((arm, sig))
            if not r:
                continue
            bpi = r["net"] / r["items"] if r["items"] else float("nan")
            bbase = base["net"] / base["items"] if base and base["items"] else None
            vs = f"{(bpi / bbase - 1) * 100:+.1f}%" if bbase else "n/a"
            w(f"| {ARM_LABEL[arm]} | {r['items']:,.0f} | {r['tx']/1e6:,.1f} | {r['ack']/1e6:,.1f} | "
              f"{bpi:,.1f} | {vs} | {r['cores']:.3f} | {r['mem']/2**20:,.0f} |")
        w("")

    w("## All signals\n")
    w("| Arm | Egress GB/day (projected) | vs contrib | CPU cores | Egress $/month at the given price |")
    w("|---|---:|---:|---:|---:|")
    totals = {}
    for arm in ARM_ORDER:
        rs = [r for (ar, _), r in rows.items() if ar == arm]
        if rs:
            totals[arm] = (sum(r["net"] for r in rs), sum(r["cores"] for r in rs))
    for arm, (net, cores) in totals.items():
        gb_day = net / secs * 86400 / 1e9
        vs = f"{(net / totals[BASELINE][0] - 1) * 100:+.1f}%" if BASELINE in totals else "n/a"
        usd = f"${gb_day * 30 * a.usd_per_gb:,.2f}" if a.usd_per_gb else "pass --usd-per-gb"
        w(f"| {ARM_LABEL[arm]} | {gb_day:,.2f} | {vs} | {cores:.3f} | {usd} |")
    w("")
    w("Egress is pod tx bytes minus the estimated ACKs for inbound OTLP. "
      "Raw snapshots: start.json, end.json.")

    text = "\n".join(out)
    (a.run / "report.md").write_text(text + "\n")
    print(text)


if __name__ == "__main__":
    sys.exit(main())
