#!/usr/bin/env python3
"""Apply the Datadog objects in datadog/ (monitors, SLOs, log index, RUM application, APM
retention filter, remediation workflow) for one demo env.

  DD_API_KEY=... DD_APP_KEY=... ENV_NAME=otel-demo datadog/local/dd-apply.py

With RUM_OUT=<file>, the RUM application's id and client token are written to that file
(mode 600) for up.sh to put in a Kubernetes secret; they are never written to git.

Every file is a template: ${ENV_NAME} is filled in, so the same definitions serve
any env. Monitors are matched by name and created or updated in place, tagged
managed_by:otel-demo-local. The log index is created or updated, then moved ahead
of "main" (in the ddstaging org, its "Reduce volume" exclusion drops 99.99% of
what falls through to it). DD_SITE is the site (default datad0g.com, where the
matt-dog org is homed). up.sh runs this; it exits 0 with a warning when the
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
API = f"https://api.{os.environ.get('DD_SITE', 'datad0g.com')}"
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
        # Save only a real change: every save restarts the monitor's evaluation, which
        # kept it OK through a problem when up.sh ran during the problem window.
        have = same[0]
        if (have["query"] == m["query"] and have.get("message") == m.get("message")
                and sorted(have.get("tags", [])) == m["tags"]
                and all(have.get("options", {}).get(k) == v for k, v in m.get("options", {}).items())):
            print(f"monitor unchanged: {m['name']} ({have['id']})")
            return
        call("PUT", f"/api/v1/monitor/{have['id']}", m)
        print(f"monitor updated: {m['name']} ({have['id']})")
    else:
        status, made = call("POST", "/api/v1/monitor", m)
        print(f"monitor created: {m['name']} ({made['id']})" if made else f"monitor not created: {m['name']} ({status})")


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


def apply_rum(app, out):
    """Create the RUM application if missing; write its id and client token to `out`."""
    _, found = call("GET", "/api/v2/rum/applications")
    same = [a for a in (found or {}).get("data", []) if a["attributes"]["name"] == app["name"]]
    if same:
        app_id = same[0]["attributes"].get("application_id") or same[0]["id"]
        print(f"RUM application exists: {app['name']}")
    else:
        _, made = call("POST", "/api/v2/rum/applications",
                       {"data": {"type": "rum_application_create", "attributes": app}})
        app_id = made["data"]["attributes"]["application_id"]
        print(f"RUM application created: {app['name']}")
    _, one = call("GET", f"/api/v2/rum/applications/{app_id}")
    token = one["data"]["attributes"]["client_token"]
    if out:
        Path(out).write_text(f"DD_RUM_APPLICATION_ID={app_id}\nDD_RUM_CLIENT_TOKEN={token}\n")
        os.chmod(out, 0o600)


def apply_retention(rf):
    """Create or update the APM retention filter, matched by name, so every span in the
    env stays searchable after Live Search's 15 minutes (the org's default retention
    keeps only a sample, which can miss the slow trace the demo opens)."""
    _, found = call("GET", "/api/v2/apm/config/retention-filters")
    same = [f for f in (found or {}).get("data", []) if f["attributes"]["name"] == rf["name"]]
    body = {"data": {"type": "apm_retention_filter", "attributes": rf}}
    if same:
        body["data"]["id"] = same[0]["id"]
        call("PUT", f"/api/v2/apm/config/retention-filters/{same[0]['id']}", body)
        print(f"retention filter updated: {rf['name']}")
    else:
        status, _ = call("POST", "/api/v2/apm/config/retention-filters", body)
        print(f"retention filter created: {rf['name']} ({status})")


def apply_connection(env):
    """Create or update the token-auth HTTP connection "<env> remediator" that the workflow
    uses to call the cluster's remediator. REMEDIATOR_URL and REMEDIATOR_TOKEN come from
    up.sh (the token from the remediator-token secret); the token is stored only here and
    in that secret."""
    url, token = os.environ.get("REMEDIATOR_URL"), os.environ.get("REMEDIATOR_TOKEN")
    if not url or not token:
        print("remediator connection skipped: needs REMEDIATOR_URL and REMEDIATOR_TOKEN (up.sh gke)")
        return
    attrs = {"name": f"{env} remediator", "integration": {
        "type": "HTTP", "base_url": url,
        "credentials": {"type": "HTTPTokenAuth",
                        "tokens": [{"name": "remediatorToken", "type": "SECRET", "value": token}],
                        "headers": [{"name": "Authorization", "value": "Bearer {{ remediatorToken }}"}]}}}
    _, conns = call("GET", "/api/v2/actions/connections")
    same = [c for c in (conns or {}).get("data", []) if c["attributes"]["name"] == attrs["name"]]
    if same:
        status, _ = call("PATCH", f"/api/v2/actions/connections/{same[0]['id']}",
                         {"data": {"type": "action_connection", "attributes": attrs}})
        print(f"remediator connection updated: {attrs['name']} ({status})")
    else:
        status, _ = call("POST", "/api/v2/actions/connections", {"data": {"type": "action_connection", "attributes": attrs}})
        print(f"remediator connection created: {attrs['name']} ({status})")


def apply_workflow(path, env):
    """Create or update the remediation workflow (matched by name) and publish it. It calls
    the cluster's remediator through the token-auth HTTP connection "<env> remediator"
    (up.sh creates both and passes REMEDIATOR_URL). safe_substitute, because the
    workflow's expressions use {{ }} and could use $."""
    url = os.environ.get("REMEDIATOR_URL")
    _, conns = call("GET", "/api/v2/actions/connections")
    by_name = {c["attributes"]["name"]: c["id"] for c in (conns or {}).get("data", [])}
    if not url or f"{env} remediator" not in by_name:
        print(f"workflow skipped: needs REMEDIATOR_URL and a connection named '{env} remediator'")
        return
    wf = json.loads(string.Template(path.read_text()).safe_substitute(
        ENV_NAME=env, REMEDIATOR_URL=url, REMEDIATOR_CONNECTION_ID=by_name[f"{env} remediator"]))
    attrs = {"name": wf["name"], "description": wf["description"], "spec": wf["spec"],
             "published": True, "tags": [f"env:{env}", "service:ad", TAG]}
    _, found = call("GET", "/api/v2/workflows?" + urllib.parse.urlencode({"filter[query]": wf["name"]}))
    same = [w for w in (found or {}).get("data", []) if w["attributes"]["name"] == wf["name"]]
    if same:
        status, _ = call("PATCH", f"/api/v2/workflows/{same[0]['id']}",
                         {"data": {"type": "workflows", "id": same[0]["id"], "attributes": attrs}})
        print(f"workflow updated: {wf['name']} ({same[0]['id']}, {status})")
    else:
        status, made = call("POST", "/api/v2/workflows", {"data": {"type": "workflows", "attributes": attrs}})
        print(f"workflow created: {wf['name']} ({(made or {}).get('data', {}).get('id')}, {status})")


def apply_slo(s):
    """Create or update an SLO, matched by name and tagged like the monitors. Prints the API's
    error text when one is refused, since a malformed SLO otherwise fails silently."""
    s["tags"] = sorted(set(s.get("tags", [])) | {TAG})
    _, found = call("GET", "/api/v1/slo?" + urllib.parse.urlencode({"query": s["name"], "limit": 50}))
    same = [x for x in (found or {}).get("data") or [] if x["name"] == s["name"]]
    method, path = ("PUT", f"/api/v1/slo/{same[0]['id']}") if same else ("POST", "/api/v1/slo")
    req = urllib.request.Request(API + path, method=method, data=json.dumps(s).encode(),
                                 headers={"DD-API-KEY": os.environ["DD_API_KEY"],
                                          "DD-APPLICATION-KEY": os.environ["DD_APP_KEY"],
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            out = json.load(r)
        sid = (out.get("data") or [{}])[0].get("id") if isinstance(out.get("data"), list) else out.get("data", {}).get("id")
        print(f"SLO {'updated' if same else 'created'}: {s['name']} ({sid})")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise Refused(f"{method} {path}: {e.code}")
        print(f"SLO not applied: {s['name']} ({e.code}: {e.read().decode()[:300]})")


def main():
    env = os.environ["ENV_NAME"]
    if not os.environ.get("DD_APP_KEY"):
        print("dd-apply: DD_APP_KEY not set; skipping monitors and log index", file=sys.stderr)
        return
    # Each step stands alone, so a key refused for one (say, log indexes) still applies the rest.
    steps = [("log index", lambda: apply_index(load(HERE / "log-index.json", env))),
             ("RUM application", lambda: apply_rum(load(HERE / "rum-application.json", env), os.environ.get("RUM_OUT"))),
             ("retention filter", lambda: apply_retention(load(HERE / "retention-filter.json", env))),
             ("remediator connection", lambda: apply_connection(env)),
             ("workflow", lambda: apply_workflow(HERE / "workflow-remediate-ad.json", env))]
    steps += [(f"monitor {f.name}", lambda f=f: apply_monitor(load(f, env)))
              for f in sorted((HERE / "monitors").glob("*.json"))]
    steps += [(f"SLO {f.name}", lambda f=f: apply_slo(load(f, env)))
              for f in sorted((HERE / "slos").glob("*.json"))]
    for name, step in steps:
        try:
            step()
        except Refused as e:
            print(f"dd-apply: the application key was refused for the {name} ({e}); skipping it.",
                  file=sys.stderr)


if __name__ == "__main__":
    main()
