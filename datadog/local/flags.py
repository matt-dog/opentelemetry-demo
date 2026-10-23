#!/usr/bin/env python3
"""Read and change the shop's feature flags through flagd-ui's API, the one way to change them.

  flags.py get adHighCpu                       print one flag's default variant
  flags.py set adHighCpu=on paymentFailure=50% set default variants
  flags.py target-product OLJCESPC7Z           make productCatalogFailure fire for one product

flagd-ui keeps the flags in memory and writes the whole set to flagd's file on every
change; it does not see edits made to the file directly. The scenarios pod, the
remediator and this script all go through the API, so nothing overwrites anything.
(Until 2026-10-23 up.sh and stage.sh edited the file, and the next scenarios write put
the API's stale copy back: the failure flags up.sh set never stayed on.)

Uses `kubectl port-forward` to svc/flagd with whatever KUBECONFIG the caller exports
(up.sh and stage.sh export one holding only the target cluster).
"""
import json
import socket
import subprocess
import sys
import time
import urllib.request


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main(argv):
    if len(argv) < 2 or argv[0] not in ("get", "set", "target-product"):
        sys.exit(__doc__)
    port = free_port()
    pf = subprocess.Popen(["kubectl", "-n", "otel-demo", "port-forward", "svc/flagd", f"{port}:4000"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    api = f"http://127.0.0.1:{port}/api"
    try:
        for _ in range(40):
            try:
                flags = json.load(urllib.request.urlopen(api + "/read", timeout=2))["flags"]
                break
            except OSError:
                time.sleep(0.25)
        else:
            sys.exit("flags.py: flagd-ui API not reachable through port-forward")
        if argv[0] == "get":
            print(flags[argv[1]]["defaultVariant"])
            return
        if argv[0] == "set":
            for pair in argv[1:]:
                name, variant = pair.split("=", 1)
                if variant not in flags[name]["variants"]:
                    sys.exit(f"flags.py: {name} has no variant {variant!r}")
                flags[name]["defaultVariant"] = variant
        else:
            # The shipped rule returns "off" on both branches, so the flag can never fire.
            flags["productCatalogFailure"]["targeting"] = {
                "if": [{"==": [{"var": "product_id"}, argv[1]]}, "on", "off"]}
        req = urllib.request.Request(api + "/write", data=json.dumps({"data": {"flags": flags}}).encode(),
                                     method="POST", headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10).read()
    finally:
        pf.terminate()


if __name__ == "__main__":
    main(sys.argv[1:])
