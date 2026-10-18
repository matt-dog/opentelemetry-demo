#!/usr/bin/env python3
"""Apply the Datadog objects in datadog/ (monitors, log index) for one demo env.

  DD_API_KEY=... DD_APP_KEY=... ENV_NAME=otel-demo-gke-blog datadog/local/dd-apply.py

Every file is a template: ${ENV_NAME} is filled in, so the same definitions serve
any env. Monitors are matched by name and created or updated in place, tagged
managed_by:otel-demo-local. The log index is created or updated, then moved ahead
of "main", whose "Reduce volume" exclusion drops 99.99% of what falls through to
it in the Datadog staging org. DD_SITE is the intake site (default datadoghq.com,
where that org is homed). up.sh runs this; it exits 0 with a warning when the
application key is missing or refused, since the demo itself works without it.
"""
import json
import os
import string
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent / "datadog"
API = f"https://api.{os.environ.get('DD_SITE', 'datadoghq.com')}"
TAG = "managed_by:otel-demo-local"


class Refused(Exception):
    pass


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={"DD-API-KEY": os.environ["DD_API_KEY"],
                                          "DD-APPLICATION-KEY": os.environ["DD_APP_KEY"],
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise Refused(f"{method} {path}: {e.code}")
        return e.code, None


def load(path, env):
    return json.loads(string.Template(path.read_text()).substitute(ENV_NAME=env))


def apply_monitor(m):
    m["tags"] = sorted(set(m.get("tags", [])) | {TAG})
    m["draft_status"] = "published"
    _, found = call("GET", "/api/v1/monitor?" + urllib.parse.urlencode({"name": m["name"]}))
    same = [x for x in found or [] if x["name"] == m["name"]]
    if same:
        call("PUT", f"/api/v1/monitor/{same[0]['id']}", m)
        print(f"monitor updated: {m['name']} ({same[0]['id']})")
    else:
        _, made = call("POST", "/api/v1/monitor", m)
        print(f"monitor created: {m['name']} ({made['id']})")


def apply_index(ix):
    name = ix["name"]
    status, _ = call("GET", f"/api/v1/logs/config/indexes/{name}")
    if status == 200:
        call("PUT", f"/api/v1/logs/config/indexes/{name}", {k: v for k, v in ix.items() if k != "name"})
        print(f"log index updated: {name}")
    else:
        call("POST", "/api/v1/logs/config/indexes", ix)
        print(f"log index created: {name}")
    # The first index whose filter matches wins and "main" is last; this filter
    # names one env, so first place is safe.
    _, order = call("GET", "/api/v1/logs/config/index-order")
    names = order["index_names"]
    if names[0] != name:
        names = [name] + [n for n in names if n != name]
        call("PUT", "/api/v1/logs/config/index-order", {"index_names": names})
        print(f"log index {name} moved to the front of the index order")


def main():
    env = os.environ["ENV_NAME"]
    if not os.environ.get("DD_APP_KEY"):
        print("dd-apply: DD_APP_KEY not set; skipping monitors and log index", file=sys.stderr)
        return
    try:
        apply_index(load(HERE / "log-index.json", env))
        for f in sorted((HERE / "monitors").glob("*.json")):
            apply_monitor(load(f, env))
    except Refused as e:
        print(f"dd-apply: the application key was refused ({e}); skipping. It needs monitors and"
              " log index read/write permissions in the org.", file=sys.stderr)


if __name__ == "__main__":
    main()
