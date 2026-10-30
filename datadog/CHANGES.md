# Changes from the upstream OpenTelemetry Demo

A running log of how this fork (matt-dog/opentelemetry-demo, branch
`datadog-demo`, `ddot-local-blog` until 2026-10-22) differs from upstream (open-telemetry/opentelemetry-demo), and
why. Newest first. The README tables describe the current state; this file keeps
the history. `ENVIRONMENT.md` records where it runs and what it depends on
outside this repo, for handover.

Nothing in the upstream source, images or Helm chart is modified. Every
difference is a new file under `datadog/`, or one of the few lines in
`.gitignore`, or an override passed to the upstream chart (0.42.1). Check with:

```bash
git diff --stat upstream/main...datadog-demo
```

Add an entry with every commit that changes the difference, and record changes
made by hand outside git under "Live changes not in git" until they are moved
into git or undone.

## Live changes not in git

| Date | Where | Change | Why | Status |
|---|---|---|---|---|
| 2026-10-25 | astronomy-db (`kubectl exec`), configmap `postgresql-init` | `GRANT MAINTAIN ON catalog.products TO astronomy_user`, live and appended to init.sql | productCatalogLockContention needs it (entry 2026-10-25) | same as what `up.sh` now does; any helm upgrade outside `up.sh` reverts the configmap |
| 2026-10-25 | flagd-ui flag set | `adHighCpu` carries a `metadata.rollback` timestamp; scheduled flags carry `metadata.nudge` | written by the remediator on every rollback and by the scheduler a minute after each change (and once by hand in a test) | expected; metadata does not affect evaluation |
| 2026-10-23 | matt-dog Incident Management | Incident #1 declared by the workflow test, still active | Resolve step refused: no Incident Management seat | Resolve by hand, or rerun once a seat is assigned |
| 2026-10-23 | matt-dog org, Mosaic | `graphing_semantic_metric_names` on (Matthew) | metrics features for OTel metric names, next to Semantic Query Mode | on; internal flag, set outside git |
| 2026-10-22 | matt-dog org settings, Preferences (UI) | OTel Semantic Query Mode on | queries match OTel and Datadog metric names | on; an org setting, no API found to set it from git |
| 2026-10-18 | ddstaging log index `ddot-lab` (UI) | Filter widened to also match `env:otel-demo-gke-blog` app services | App logs fell through to `main`, which drops 99.99% | Redundant since `fc642ea5` (the env has its own index, first in order); can be reverted to `env:ddot-lab service:orders-*` |

## Log

### 2026-10-30 · Step 6 opens one end-to-end checkout trace; the cart error is a detour
- **What (Doc only):** step 6 and step 5's transition link to trace `bd7afca2f119f9e5f4ef3b3cbe93adc0`
  (2026-10-30 18:11 UTC), opened from checkout's `publish orders` span: 72 spans from load-generator
  through checkout and cart to fraud-detection's Kafka consume (Matthew). The presenter unchecks Errors.
  An optional detour in step 6 shows the trace's two errors: checkout's EmptyCart call to cart fails with
  "Wasn't able to connect to redis" (the upstream `cartFailure` flag, held at 10%), yet the order completes.
- **Why:** opened from fraud-detection, the trace view showed the consume span alone, though the API
  returns it inside checkout's trace with checkout's `publish orders` as parent (checked 2026-10-29).
  Opened from checkout, the waterfall shows the whole flow.
- **Open:** the link is a fixed trace from today, outside the pinned 27 Oct window, so it stops working
  when the spans pass retention (likely about 15 days; unverified for matt-dog).

### 2026-10-28 · Profiling out of the presenter flow; the span Logs tab works
- **What (Doc only):** Chapter 1 drops the profile steps (old 6 and 8). Steps renumbered: Kafka trace 6,
  collector fleet 7, the fix 8. The transitions, Outro, key messages and discovery table no longer mention
  the profile.
- **Why:** the Host Profiler undercounts ad's CPU during the window (about 180 times, DEMO-PLAN.md known
  limits), so every view of it shows CPU going down during a CPU problem, and APM's Profiling page does not
  show these profiles. Matthew's call; it can come back once the profiler team answers.
- **Logs:** the span's Logs tab now shows ad's logs (Matthew, 2026-10-28), so the "Open" item about the
  "Get started with Log Management" placeholder in the entry below is resolved. The duplicate stdout logs
  remain.

### 2026-10-28 · Dashboard: Host Profiler CPU against the container's
- **What:** `datadog/dashboards/profiler-vs-container-cpu.json` (dd-apply): the ad container's CPU as ms per
  minute (cores x 60,000) as a number and a graph with the 300m limit at 18,000, beside a `flame_graph`
  widget (`profiling_aggregated_profile`, `service:ad`) whose header gives the profiler's average CPU time.
- **Why:** Matthew asked for proof of the undercount (DEMO-PLAN.md, known limits) to share with the Host
  Profiler team. The widget schema is not documented; the API accepts `query_string` and `group_by` on
  the query and rejects other fields.
- **Verified:** with the widget Matthew fixed in the UI (`"family": "ebpf"` selects Host Profiler data;
  the profile type and granularity need a `service:` in the search first), 2026-10-27 19:31 to 19:40 UTC
  reads 17,993 ms per minute in the container and 100 in the profiler. At idle the two roughly agree
  (about 180 against 90 to 140). Those are the widget settings now in git.

### 2026-10-28 · Presenter script: steps 2, 4, 5, 6 follow what the screens show
- **What (Doc only):** step 2 starts from the pod monitor's page (its Changes band puts the adHighCpu
  change at each :30); step 4 uses the span's Infrastructure tab (pod CPU flat at 0.3 cores) in place of a
  metrics tab; step 6 uses the ad pod's Profiles tab in Kubernetes Explorer and names
  `CPULoad$Logarithmizer.run`; links re-pinned to 19:25 to 19:48 UTC on 2026-10-27. DEMO-PLAN.md records
  the profiler's CPU undercount.
- **Open:** the span's Logs tab shows Datadog's "Get started with Log Management" placeholder in place of
  ad's logs, though the logs exist and carry the trace and span IDs (checked through the API for trace
  `1e02209f3b6dbab0db337b1d31c7b3e9`). Most likely an org entitlement on matt-dog; unverified. ad and
  checkout also send every log twice (OTLP with IDs, and stdout through the file log receiver without).

### 2026-10-27 · 6-minute wait; Postgres fix verified
- **What:** the workflow waits 360 s, down from 480. The pod monitor's message and the Doc's step 10 and
  Setup row say so.
- **Why:** the pod monitor fired at :34 to :35 in 24 of 25 hours, but at 18:37 in the 18:30 window. ad was
  at its full 0.30-core limit from 18:31, so the data was ready by :34 and the delay was the monitor's
  evaluation. With 8 minutes the rollback landed at 18:45:06, and "off" at 18:45:18 cannot be told apart
  from the schedule's :45 switch. With 6 minutes the rollback lands at :40 to :43 when the monitor fires at
  :34 to :37. ad stays red in Kubernetes Explorer from about :31 to :41.
- **18:30 window, after the Postgres fix:** no restarts outside email. Postgres peaked at about 96 MB
  during the lock, just under the old 100Mi (105 MB) limit, which is why some hours went over. No
  "Order parsing failed" errors. product-catalog p95 reached 28 s under the lock.

### 2026-10-27 · Postgres memory limit 300Mi: the lock chapter OOM-killed it
- **What:** `values-local.yaml` sets astronomy-db to a 300Mi memory limit (request still the chart's
  100Mi). Applied live with `kubectl patch` at 18:10 UTC; the next `up.sh` sets the same through Helm.
- **Why:** astronomy-db had restarted 43 times since the GKE node upgrade on 2026-10-26 06:42, rising to
  about four OOM kills an hour (22 restarts at 12:00, 43 at 17:00 on 2026-10-27). The last one was at
  17:44, inside the :42 to :45 lock chapter. The lock queues every catalog read as a waiting
  connection, and at the chart's 100Mi limit Postgres ran out. With no volume, each kill wiped the
  database and ran init.sql again (the configmap still holds the MAINTAIN grant). The catalog was down
  while Postgres restarted, and accounting logged "Order parsing failed" in pairs at :36 to :47 since
  about 10:44. I missed the restarts when scoring windows, because I did not check astronomy-db.
- **Verified:** after the patch, the grant is in place, `catalog.products` has 10 rows, and product-catalog
  reads from the database again. A window with the new limit has not run yet.

### 2026-10-26 · Only the pod monitor starts the workflow; 8-minute wait
- **What:** the latency monitor no longer mentions the workflow; the pod monitor does, alone. The wait is
  480 s, down from 600. The Doc's step 10 and Setup row say so.
- **Why (16:30 window):** the pod monitor fired at 16:35 and started the workflow at 16:35:06. The latency
  alert came late again (16:39), started a second run (the 20-minute rate limit is per monitor, not per
  workflow), then recovered on its own at 16:42. The first run rolled back at 16:45:10, the same minute the
  schedule turns the flag off, so it is unclear which one did it. The pod monitor has fired on time in all
  15 hours since it was built; with 8 minutes the rollback lands at about :43, ahead of the schedule. One
  trigger also means one run per hour.

### 2026-10-26 · Pod monitor also starts the workflow; rollback retries; 14 windows scored
- **What:**
  - The pod monitor mentions `@workflow-otel-demo-remediate-ad` too. The workflow runs at most once per
    20 minutes, so whichever ad monitor fires first starts it.
  - The workflow's rollback retries every 30 s, 4 times, then ends in a no-op step (`Rollback_failed`).
  - The latency monitor's message no longer mentions stage mode or `stage.sh`.
- **Why (02:30 to 15:30 UTC, 14 windows):**
  - The pod monitor fired at :34 and recovered at :42 to :47 every hour.
  - The nudge gave a second "on" evaluation at :31 every hour, and ad picked up every :30 edge.
  - The latency alert came late in 4 hours (05:41, 12:43, 13:40, 14:40). With the 10-minute wait, the
    rollback then landed at :52 to :54, after the schedule had already turned the flag off at :45, so the
    workflow fixed nothing in those hours. The pod monitor, always at :34, puts the rollback at about :44.
  - At 06:43 the rollback got a 502 from the load balancer. GKE's maintenance window (06:00 to 10:00 UTC)
    was recreating nodes: ad came back as a new pod (`ad-66c6794c6-dr5xd`) and flagd restarted (adHighCpu
    "off" at 06:40). A retry covers a short outage like that.
  - The workflow succeeded in the other 12 hours.
- **Not yet verified:** a window with both changes.

### 2026-10-26 · A monitor on the ad pod; an always-open alert; the workflow waits 10 minutes
- **What:**
  - `monitors/ad-pod-cpu-limit.json`: the ad container's CPU over 90% of its limit for 3 min, grouped
    by `pod_name`, on the Collector's Kubernetes metrics.
  - `monitors/product-catalog-error-rate.json`: product-catalog errors over 5% for 10 min. It is in
    Alert all the time, from the baseline productCatalogFailure rule (one product, about 7.6% of
    lookups).
  - `workflows/remediate-ad.json`: waits 600 s before rolling back, up from 180 s.
  - Doc: the Setup row now gives the always-open alert and the 10-minute window; step 10 says ten
    minutes. Step 1 now starts in Kubernetes Explorer (Matthew): sort by CPU usage/limits, open the ad
    pod's Monitors tab, open the pod monitor. Its message links to the ad latency alert, the ad service
    page and ad's change events, which is how the presenter follows it into step 2.
- **Why:** Matthew opens in Kubernetes Explorer and wants to see the problem there. Its Monitors column
  shows monitors "tagged, scoped, or grouped" for a resource. The ad monitors are scoped by
  `service:ad` on trace metrics, and those carry no pod or deployment tags (`kube_deployment` and
  `pod_name` are N/A), so the column stayed empty. A monitor grouped by `pod_name` on the Kubernetes
  metrics can sit on the pod. The 10-minute wait keeps ad at its limit from about :31 to :43 instead
  of about 5 minutes, which fits Chapter 1's length ("while we've been talking, Datadog fixed it").
  The always-open alert gives a presenter a starting point outside the window without breaking ad's
  SLOs. Matthew chose this over making ad fail all day with `adFailure`, which would have taken the
  availability SLO to about 92% for a week.
- **Verified:** the pod monitor evaluates one group, `pod_name:ad-66c6794c6-l79bn` (OK between
  windows). The product-catalog monitor went to Alert within a minute. The live workflow has
  `durationSeconds: 600`. In the 16:30 window, ad's container ran at 0.30 of its 0.30-core limit from
  16:31 to 16:38. Not yet checked: whether Explorer's Monitors column shows the pod monitor, and a
  full window with the new wait.

### 2026-10-25 · Scheduler notifies each changed flag twice
- **What:** `scenarios.yaml` writes each flag it changed again a minute later with a fresh
  `metadata.nudge` stamp; the variant is whatever flagd-ui holds then, so a rollback in between sticks.
- **Why:** in the 04:30 window ad never evaluated adHighCpu "on". flagd-ui held "on" all window (the
  scheduler set it back to off at 04:45), but ad served its cached "off": no latency, no alert, no
  rollback. That is the second time ad missed a flagd change notification (the first: 19:35 on
  2026-10-24, after a rollback). The cause is not known; the other services saw their changes at 04:30
  (payment errors, Kafka lag 1,410, email restarts, the lock logged). A metadata write makes flagd
  notify again (see the remediator fix below), so a second notification a minute later covers a miss.
- **Verified:** at 05:30 ad evaluated "on" at 05:30:13 and again at 05:31:14 (the nudge), alerted at
  05:32:52, rolled back at 05:35:48, "off" at 05:35:49, monitor OK at 05:41. The other chapters showed too:
  payment errors, agent spans 73 to 491 per 5 min, Kafka lag 1,520, email restarts 16 to 21, product-catalog
  p95 25.5 s. The nudge has not yet met a real missed notification.
- **Windows since the first full one:** 03:30 every chapter, rollback 03:35:48; 04:30 every chapter
  except ad (above).

### 2026-10-25 · Presenter dashboard for the window; Close line corrected
- **What:** `datadog/dashboards/demo-window.json`, applied by `dd-apply.py` (new step, matched by title):
  a note with the schedule and one timeseries per chapter (ad p95 with the 20 ms alert line, payment
  errors, RUM image loads over 3 s, agent spans, Kafka lag, locks on catalog.products by mode,
  product-catalog p95, email restarts and the OOMKilled reason), with the scheduler's and workflow's
  change events on the ad and payment widgets. The Doc's Setup table links it. The Doc's Close no
  longer offers "the same trace in Jaeger" as a screen: the daemon Collector does send every trace to
  the in-cluster Jaeger, but it is reachable only by port-forward.
- **Why:** one screen shows every chapter of the shared window at once, which is the tool-consolidation
  point, and tells a presenter which chapters are live. Planned since 2026-10-22 (DEMO-PLAN.md, item 7).
- **Verified:** created, then updated in place on a second run; the API kept every widget, marker and
  event overlay. Each widget's query was checked against the 02:30 window's data; the rendered page
  has not been looked at.

### 2026-10-25 · Three more chapters in the :30 to :45 window; lock contention fixed; rollback always refreshes ad
- **What:**
  - `scenarios.yaml`: every problem runs in one window on staggered starts: adHighCpu :30, paymentFailure
    25% :31, aiRunawayAgent :32, imageSlowLoad 5s :33 (each to :45), kafkaQueueProblems :35 to :41
    (change events on fraud-detection), emailMemoryLeak 10000x :38 to :44, productCatalogLockContention
    :42 to :45. The cartFailure baseline is 10%, down from 100%.
  - `up.sh`: after the helm upgrade, it appends `GRANT MAINTAIN ON catalog.products TO astronomy_user`
    to the chart's `postgresql-init` configmap, and restarts astronomy-db if the grant is missing. It no
    longer sets flags itself, since the scheduler holds them. The `bash -n` syntax check passes; the block
    has not run on a fresh cluster.
  - `remediator.yaml`: `/rollback-flag` always writes, stamping `metadata.rollback` on adHighCpu.
  - `contrib-collector.yaml`: the optional `postgresql.database.locks` metric is on.
- **Why:**
  - Tool consolidation: each problem is a chapter on its own service and Datadog product, all from
    OTel data, and one window (live or pinned) holds them all.
  - cartFailure at 100% failed every checkout, so nothing published to Kafka from 2026-10-23 14:00 to
    2026-10-24 14:00 (and again after 18:11).
  - Lock contention never worked here. The 3.1.0 product-catalog takes `LOCK TABLE ... ACCESS EXCLUSIVE`,
    but chart 0.42.1's init.sql grants only SELECT: "pq: permission denied for table products". It logs
    only over OTLP, so `kubectl logs` showed nothing. MAINTAIN (Postgres 17+) allows the lock without
    data writes. astronomy-db has no volume and runs init.sql at every start.
  - At 19:35 on 2026-10-24 a rollback succeeded (flagd reloaded the file), but ad kept evaluating
    adHighCpu "on" until the next write at 20:30. Most likely ad's flagd provider missed the change
    notification; that is not proven. The monitor stayed in alert, and the workflow's 20-minute rate
    limit swallowed the 20:30 window. A metadata write makes flagd notify ad for that key: tested by
    hand at 01:31 (ad re-evaluated 3 s later) and through the endpoint at 02:16 (1 s later,
    `refreshed: true`). It has not been tested against a real missed notification.
- **Verified (one run each, 2026-10-25, outside the window):**
  - productCatalogLockContention, 90 s: product-catalog p95 21 ms to 26.8 s, the slowest Postgres
    query 29.6 s, frontend p95 15 s, ad hits down about 40%, checkouts 1 to 2 a minute. A `LOCK TABLE`
    span shows in traces.
  - kafkaQueueProblems, 3 min: fraud-detection lag 0 to 1 rose to 909, drained within a minute of off;
    checkout logs "overloading queue now".
  - emailMemoryLeak: 1000x for 4 min took email from 55 to 96 Mi of its 100 Mi limit, then Ruby freed
    it, with no restart. 10000x for 60 s: OOMKilled within about 40 s. Datadog has
    `k8s.container.restarts` and `kube_pod_container_status_last_terminated_reason{reason:oomkilled}`.
    Checkout only warns ("failed to send order confirmation"); its errors stay at baseline.
- **First full window, 2026-10-25 02:30 (one run):** every chapter showed. ad p95 46 to 60 ms
  (:34 to :38), workflow rollback 02:38:47, monitor OK 02:43. payment had 0 errors in the 15 min before
  and 9 of 31 calls failed in the window. Agent spans went from 73 to 101 per 5 min before to 257 to 445.
  RUM had 206 image loads over 3 s, none before. fraud-detection lag reached 606, back to 0 a minute after
  :41. product-catalog p95 was 12 to 25.5 s, and `postgresql.database.locks` showed the
  AccessExclusiveLock on products with up to 18 AccessShareLocks waiting. email was OOMKilled 5 times
  (:38 to :43) and was running again at 02:45:38, after its CrashLoopBackOff delay. Payment calls fell
  about 40% across the window (fewer orders while the shop slows).
- **Presenter script:** the Google Doc has chapters: Chapter 1 is the earlier script, unchanged
  (Matthew's screenshots kept); Chapters 2 to 6 (errors, RUM, AI, data layer, Kubernetes) replace
  "Optional stories"; a tool-consolidation key message; window notes for :30 to :45.
- **Shared loop, 2026-10-24 19:30 to 2026-10-25 01:30 (7 windows, first four patterns):** 6 windows
  rolled back by the workflow; 20:30 missed (above). The alert came 1 to 10 min after :30; at 01:30,
  p95 stayed at 3 to 5 ms for 10 minutes with the flag on before it rose.

### 2026-10-24 · GKE maintenance window; presenter script updated for the shared demo
- **What:** the cluster's maintenance window is daily 06:00 to 10:00 UTC (`gcloud container clusters
  update`, also run by `up.sh gke`). The Google Doc script lost its stage.sh setup: presenters use
  the live :30 to :45 window or pin the last one; step 3 and step 10 match the current workflow.
- **Why:** GKE's automatic upgrade recreated all nodes at 17:26 UTC mid-demo window (entry below).
  GKE needs at least 48 hours of maintenance windows per 32 days, so a weekly 4-hour slot is
  refused; daily 4 hours is the smallest regular shape outside both US and EU working hours.

### 2026-10-24 · Workflow simplified; scheduler retries failed edges and holds the baseline flags
- **What:** `workflows/remediate-ad.json` drops the CPU-limit lift and restore: open an incident if
  none is open for ad, wait 3 min, roll back adHighCpu. `scenarios.yaml` marks an edge done only
  after flagd accepts the write, and holds a baseline (`baseline.json`: cartFailure 100% and the
  productCatalogFailure rule for OLJCESPC7Z), reapplied whenever it differs.
- **Why:** changing the CPU limit restarted the ad pod (cold-JVM spike, second alert). Over the
  next 12 hours the simplified loop ran in 11: alert 1.7 to 4.7 min after :30, rollback 3 min
  later, incidents steady at 2. The 08:30 window never started: adHighCpu evaluated off all window,
  consistent with a failed write the old code recorded as done (the pod's log was lost). At 17:14
  and 17:26 UTC GKE upgraded the control plane and recreated all three nodes (REGULAR channel);
  flagd's restart reset the baseline flags `up.sh` set once, and the fresh ad pod spiked p95 to
  1.9 s during the 17:30 window.
- **Verified:** new pod restored the baseline once (cartFailure 100%, rule fires), then a quiet log.
  A misplaced block briefly printed empty "set" lines (18:11 to 18:13, no flag changed, no
  duplicate events); fixed the same minute.
- **Open:** GKE automatic upgrades recreate the nodes during the day; a maintenance window or
  exclusion would keep them off demo hours (DEMO-PLAN.md).

### 2026-10-24 · Shared, always-on demo: no stage mode; the workflow runs every hour
- **What:** `workflows/remediate-ad.json` drops the stage check: on every ad latency alert it opens
  an incident only if none is open for ad (option B: never more than one, never resolved, no seat
  needed), waits 6 min, lifts ad's CPU limit, waits 3 min, rolls back adHighCpu, waits 1 min, and
  restores the 300m limit; trigger rate limit 20 min. `remediator.yaml` drops its stage-mode
  refusal and adds `POST /restore-cpu-limit`. `scenarios.yaml` acts only at window edges (and once
  at startup), so a rollback in between sticks until the next window.
- **Why:** Matthew, 2026-10-24: there is no stage mode; one demo serves many people at once, any
  time. Presenters use the live :30 to :45 window or pin a past one (traces are kept at 100%).
- **Verified (05:30 UTC, unattended):** flag on 05:30:19; monitor alert about 05:37; workflow
  05:37:44, every step succeeded; no new incident (#1 and #2 open); limit lifted 05:43:50; the
  schedule's edge turned the flag off at 05:45, before the workflow's rollback (05:46:51, no
  change); limit restored 05:47:52.
- **Open:** (1) changing the CPU limit restarts the ad pod, and the cold JVM spiked p95 to 59 ms and
  re-alerted the monitor at 05:46; (2) the alert came 7 min after the flag (about 2.5 min before),
  so the fixed waits ran past the window; (3) the problem throttled less consistently this hour
  (p95 3 to 6 ms most minutes, about 100 ms in some), cause not yet known.

### 2026-10-24 · imageSlowLoad scheduled; resolve-incident workflow built (off); problem-pattern test
- **What:** `scenarios.yaml` adds imageSlowLoad 5s from :46 to :52 (change events on frontend).
  `workflows/resolve-ad-incident.json` (new) and `workflows/remediate-ad.json` (moved from
  `workflow-remediate-ad.json`); `dd-apply.py` applies every file in `workflows/`, needs the
  remediator connection only for workflows that call it, and runs workflows before monitors.
  `apply_slo` now matches by the `managed_by` tag and exact name.
- **Why:** more problem patterns for the unattended demo, and incidents that open and close with
  the alert (DEMO-PLAN.md). The SLO name search missed names starting with "[", so a rerun
  created duplicates (two deleted the same minute).
- **Verified:** test of five flags at once (results in DEMO-PLAN.md, Problem patterns); the new
  schedule loaded and set paymentFailure at 05:00 UTC; two reruns of `dd-apply.py` left exactly
  two SLOs. The resolve workflow is published but no monitor mentions it yet.
- **Live, undone:** a stalled test left paymentFailure, kafkaQueueProblems,
  productCatalogLockContention, imageSlowLoad and intlShippingSlowdown on, with the schedule
  paused, from 02:29 to 04:52 UTC; graphs show it. Reset at 04:52.

### 2026-10-23 · SLOs and an error-rate monitor for the ad service
- **What:** `local/datadog/slos/ad-latency.json` (time slice: per-minute p95 under 20 ms, 99%, 7d),
  `slos/ad-availability.json` (hits minus errors over hits, 99.9%, 7d) and
  `monitors/ad-error-rate.json`. `dd-apply.py` applies SLOs (matched by name, tagged
  `managed_by:otel-demo-local`) and prints the API's error text if one is refused.
- **Why:** the ad service page showed no SLOs and only latency monitors; Matthew asked for SLOs
  and a service health monitor. Everything uses the OTel-derived `trace.grpc.server.request` metric.
- **Verified (API):** latency SLO 90.3% over 24h (the hourly windows burn it), availability 100%,
  error-rate monitor OK. Also checked: the anomaly monitor had 12 false alarms in 24h (DEMO-PLAN.md).

### 2026-10-23 · Workflow declares and resolves an incident; findings on flags and change tracking
- **What:** `workflow-remediate-ad.json` gains `Declare_incident` (after the stage check: SEV-3,
  services ad, a timeline note) and `Resolve_incident` (after the flag rollback). The presenter
  script moved to a Google Doc (link in ENVIRONMENT.md); DEMO-PLAN.md records the findings below.
- **Why:** the ad service page showed no incidents, because nothing declared one. Stage mode
  only, so the hourly schedule doesn't open 24 incidents a day.
- **Verified (API, stage mode, 21:02 UTC):** every step through the rollback succeeded and incident
  #1 was created with services ad. `Resolve_incident` failed with 403 "Seat Required": updating an
  incident needs an Incident Management seat for the workflow's owner.
- **Also found:** flagd and ad spans carry OpenTelemetry's `feature_flag.*` attributes; change
  tracking has no OTLP source and OTel no flag-change convention, so the change event stays an
  Events API call (DEMO-PLAN.md, Findings).

### 2026-10-23 · Act 3 rebuilt on Workflow Automation calling our remediator; flags only through flagd-ui's API
- **What:**
  - `local/remediator.yaml`: a stdlib Python endpoint (stage check, lift ad's CPU limit, roll back
    `adHighCpu`; actions only in stage mode; change events) behind a GKE Ingress with a
    Google-managed certificate, a Cloud Armor policy admitting only Datadog's webhooks ranges, and
    a bearer token. `up.sh` (GKE) reserves the IP, sets the policy and token, applies it.
  - `dd-apply.py`: the token-auth connection and the workflow (`workflow-remediate-ad.json`,
    monitor and API triggers). The latency monitor mentions it on Alert.
  - `local/flags.py`: every flag change through flagd-ui's API; `up.sh` and `stage.sh` use it.
- **Why:**
  - No Private Action Runner (Agent-based). Matthew chose a workflow calling our endpoint.
  - flagd-ui keeps flags in memory and ignores edits to flagd's file; `up.sh` and `stage.sh` edited
    the file and the scenarios pod's next API write put the stale copy back. So `up.sh`'s failure
    flags (cartFailure 100%, the productCatalogFailure rule) had not been in effect, and a
    remediation read could disagree with `stage.sh`. `paymentFailure` is owned by the schedule
    (25% from :00 to :10), so `up.sh`'s 50% never held either way.
  - Change events accept `changed_resource.type` feature_flag, configuration or anomaly only.
- **Verified:** workflow run in stage mode, every step succeeded, p95 102 ms to 7 to 15 ms; outside
  stage mode it stops at the check; Cloud Armor 403 from outside, 401 without the token; flag
  file, API and remediator agree after `stage.sh` and `flags.py`.

### 2026-10-23 · Private Action Runner removed; Mosaic flag on
- **What:** the runner (Helm release `par`), its two connections and the remediation workflow
  deleted; `par-values.yaml` and `workflow-remediate-ad.json` removed; the monitor no longer
  mentions the workflow. `graphing_semantic_metric_names` is on in the org (Matthew).
- **Why:** the runner is Agent-based, which the demo's no-Agent story can't carry. Act 3 is
  redesigned without it (DEMO-PLAN.md). The runner's registration still shows in Action Catalog
  > Private Action Runners until deleted there (no API found).

### 2026-10-22 · Act 3 (auto-remediation) built, not yet run end to end; step 1 rehearsed
- **What:** `local/datadog/workflow-remediate-ad.json` (published by `dd-apply.py`, which resolves
  the runner connections by name), `local/par-values.yaml`, the monitor's `@workflow` mention on
  Alert, `stage.sh stop` restoring ad's 300m limit, `stage.sh status` showing it. The latency
  monitor now evaluates per-minute p95 (`rollup(avg, 60)`), no warning band.
- **Why:** Matthew asked for a workflow that relieves the symptom (CPU limit) and then applies the
  real fix (flag rollback). The workflow acts only when `stage.sh` has paused the schedule, so the
  hourly windows don't fight it. Lifting the limit, not raising it: see DEMO-PLAN.md, Act 3.
- **Verified:** step 1 on cue (Alert at +3.5 min, held 10 min). Not verified: the workflow run.

### 2026-10-22 · Demo plan built: OTel names on metrics, DDOT SDK on fraud-detection, contrib Collector, stage cue
- **What:**
  - `DEMO-PLAN.md` (replaces `TOUR-PLAN.md`) and `DEMO-SCRIPT.md`, the presenter's walkthrough with links.
  - `kube-stack-values.yaml`: `metrics.resource_attributes_as_tags` on every collector's Datadog exporter.
  - `values-local.yaml`: fraud-detection runs the DDOT SDK (the swap already tried on `ad`).
  - `contrib-collector.yaml`: an upstream collector-contrib 0.161.0, Operator-managed, with the
    `postgresql`, `redis` and `kafka_metrics` receivers and the datadog extension.
  - `stage.sh`: start and stop `adHighCpu` on cue, with its change event, pausing the schedule.
  - `dd-apply.py`: an APM retention filter (`retention-filter.json`, `env:<env>` at 100%); monitors
    saved only when their definition changed. `ad-latency-threshold.json` now alerts at 20 ms.
  - `up.sh`: keys from the environment when set, else 1Password, read once each.
- **Why:**
  - Metric queries by OTel attribute names (`k8s.cluster.name`) found nothing: the exporter keeps
    only the Datadog names (`kube_cluster_name`) by default. That was the `N/A` cluster tag.
  - The DDOT Collector ships no PostgreSQL, Redis or Kafka metrics receivers (checked in the binary).
  - The org's default trace retention kept only a sample, so the slow GetAds traces were not
    searchable after 15 minutes.
  - The 50 ms monitor stayed OK through 25 minutes at about 100 ms p95. Every `dd-apply.py` run
    re-saved it, which restarts evaluation. A rehearsal then showed the real cause: the monitor took
    p95 over buckets holding only a few ad requests and averaged them, well below the per-minute p95
    the graphs show, so it sat in Warn or flapped. It now evaluates `p95:...rollup(avg, 60)` over 3
    minutes, critical at 20 ms, no warning band.
  - 1Password prompts timed out mid-run.
- **Verified (API):** p95 3 to 6 ms baseline, about 100 ms within 2 minutes of `stage.sh start`; the
  slow trace's 4 logs by trace ID including "High CPU-Load problempattern enabled"; ad container at
  0.298 of a 0.3 CPU limit by OTel names; Host Profiler profiles for ad, PostgreSQL, Kafka, Envoy; a
  44-span checkout trace across 11 services, fraud-detection on the DDOT SDK, the same in Jaeger;
  PostgreSQL, Redis and Kafka metrics with OTel tags; RUM sessions. The contrib Collector sets
  `datadog.host.name` from its node, like the DDOT ones; without it its metrics landed on a
  duplicate `<node>.dd-dev-otelpmdev` host. Not checked through the API:
  dashboards lighting up, the contrib row in Fleet Automation, the profile's function view.

### 2026-10-22 · kube-stack installer copied into the repo; old branch deleted
- **What:** the kube-stack installer `up.sh` runs is now `local/kube-stack/` (copied unchanged from
  DataDog/opentelemetry-examples at 4e131eb, the abandoned local branch
  `matthew-david/blog-jaeger-datadog`); `KUBE_STACK_DIR` defaults to it. The remote branch
  `ddot-local-blog` was deleted; every commit on it is in `datadog-demo`.
- **Why:** the demo depended on an unpushed branch on one laptop, so nobody else could run it.
  The enrichment learned on the old branch (one host name per node, `datadog.host.name` from
  `k8s.node.name`, Kubernetes tags on spans) is already in this branch's history and config.

### 2026-10-22 · Branch renamed `datadog-demo`; ENVIRONMENT.md for handover
- **What:** branch `ddot-local-blog` renamed `datadog-demo`. New `ENVIRONMENT.md`: the Datadog
  org, keys (as `op://` references), objects in the org, org settings and internal flags, the GKE
  cluster, and code outside this repo. Blog wording removed from `local/README.md`.
- **Why:** the demo is no longer for the DDOT launch blog. It is the general demo, to be handed
  over to demo engineering, so the environment is recorded next to the changes from upstream.

### 2026-10-22 · Local demo sends to the matt-dog org on datad0g.com
- **What:** `local/up.sh` defaults to `DD_SITE=datad0g.com` and reads its keys from
  `op://Employee/ddot-lab/matt-dog-dd-api-key` and `matt-dog-dd-app-key` (was ddstaging on datadoghq.com,
  `DD_API_KEY` and `DD_APP_KEY` fields). The GKE target is cluster `otel-demo`, env
  `otel-demo` (was `otel-demo-blog`, env `otel-demo-gke-blog`). It now checks the API key against the site before installing anything,
  and prints an `app.$DD_SITE` link. The RUM snippet's `site` comes from `DD_RUM_SITE` in the
  rum-config secret (was hardcoded `datadoghq.com`). `dd-apply.py` and `scenarios.yaml`
  default to datad0g.com. The Anthropic key stays on `ddot-lab`.
- **Why:** an org of Matthew's own gives full control over feature flags, monitors and
  indexes without sharing ddstaging with other teams. All of it can still point back at
  ddstaging by setting `DD_SITE`, `DD_API_KEY_REF` and `DD_APP_KEY_REF`.
- **dd-apply.py:** each object (log index, RUM application, each monitor) is applied on its own,
  so a key refused for one still applies the rest (was: the first refusal skipped everything).
  In matt-dog the log index is optional; `main` has no exclusion filter there. Creating it is
  refused (403) even with an unscoped app key, so the index is skipped there for now.
- **Cluster:** `otel-demo-blog` (ddstaging) and the old Home-tab `otel-demo` (asleep) were deleted
  and `otel-demo` recreated from this branch. Data confirmed in matt-dog: logs and spans from every
  shop service, 963 active metrics, 6 hosts. RUM application and both monitors created there.

### 2026-10-19 · Monitors: 15-minute recovery; threshold monitor applied
- **What:** `ad-latency-anomaly.json` recovers after 15 minutes without out-of-band points
  (`recovery_window: last_15m`, was 3). `ad-latency-threshold.json` applied (monitor 334131509).
- **Why:** with a 3-minute recovery the anomaly monitor went green about 5 minutes into the
  incident, because `basic` absorbs the new level, while latency was still high. It now stays red
  from about :33 to about :47, which matches the incident. The threshold monitor is red for the whole
  :30 to :45 window.

### 2026-10-19 · One host name per node
- **What:** `local/kube-stack-values.yaml` adds `resource/dd_hostname` to every Datadog pipeline of the
  daemon, cluster and host-profiler collectors: `datadog.host.name` from the item's `k8s.node.name`,
  else the collector's own node (`OTEL_K8S_NODE_NAME`). Both Datadog exporters send
  `kube_cluster_name`, `cluster_name` and `env` as host tags. `resource/hostname` is defined too,
  because the base's `null` for it survives `helm --reuse-values` and the collector rejects an empty
  processor (one daemon pod crash-looped on that before the fix). `up.sh` fills `__ENV_NAME__` into a
  temp copy of the overlay. Applied with `helm upgrade --reuse-values` on the kube-stack release.
- **Why:** each node showed as three hosts: `<node>` (the exporter's own host), `<node>.<project>`
  (Datadog's GCP rule: detector `host.name` plus `cloud.account.id`) and
  `<node>.c.<project>.internal` (the host profiler). Tags sat on one, metrics on another, so the host
  map's cluster filter and the profiling host filter came up empty. Datadog resolves
  `datadog.host.name` first (docs: opentelemetry/mapping/hostname). Verified 01:48Z: spans, node
  metrics and profiles report only the three bare node names; the old series stopped at 01:47:58Z.
- **Notes:** the shop's browser spans (`frontend-web`) now have no host, which is right for spans
  from a browser. `git.repository.id` on spans doesn't come from the pipeline.

### 2026-10-18 · DDOT SDK on ad: traces work, logs don't yet; kept opt-in
- **What:** `local/ddot-sdk-ad.values.yaml` (not applied by `up.sh`): an init container copies the
  agent jar from `datadog/dd-otel-autoinstrumentation-java:1.67-preview`, `JAVA_TOOL_OPTIONS` points
  at it in place of the image's upstream OTel agent, plus `OTEL_TRACES_EXPORTER=otlp` and
  `DD_TRACE_OTEL_ENABLED`, `DD_LOGS_OTEL_ENABLED`, `DD_METRICS_OTEL_ENABLED` (the settings on the DDOT
  SDK swap slide). Also `local/datadog/monitors/ad-latency-threshold.json`, a p95 > 50 ms monitor
  that stays in alert for the whole :30 to :45 window (applied with the next `dd-apply.py` run).
- **Why:** slide 24's before and after. Ran 23:12 to 23:16Z and 23:19 to 23:22Z. Traces work:
  spans arrive with `telemetry.sdk.name: datadog`, version 1.67.1, the right env and Kubernetes
  tags (they were only slow to index; an earlier entry here said they never arrived, which was
  wrong). Logs don't: none of the pod's logs carried trace context and nothing came through its
  OTLP log export, which breaks trace-to-logs on slide 9. So `ad` runs the upstream agent until
  that is fixed. The tracer's telemetry and debugger also try `localhost:8126` (no Agent); harmless.
- **Also:** RUM's `traceparent` wins over the shop's OTel browser SDK on API calls (checked with a
  headless browser: `tracestate: dd=s:1;o:rum`), so RUM actions open their backend traces and the
  shop's own browser spans become separate traces.

### 2026-10-18 · RUM with the Datadog Browser SDK; the shopper asks the AI assistant
- **What:**
  - `local/datadog/rum-application.json`: the RUM application, created by `dd-apply.py`, which
    writes its id and client token to a mode-600 temp file (`RUM_OUT`). `up.sh` turns that into
    the `rum-config` secret and now runs `dd-apply.py` before the shop is installed.
  - `local/frontend-proxy/envoy.tmpl.yaml`: the demo image's Envoy template (3.1.0) mounted over
    it, plus a Lua filter that inserts the RUM Browser SDK (v7, CDN) after `<head>` on the shop's
    and the chatbot's pages. It asks for an uncompressed body on page paths only; API, assets,
    Jaeger, Grafana and the flag UI are skipped. RUM service `frontend-web` (the name the shop's
    browser spans already use), Session Replay at 100%, `allowedTracingUrls` on the shop's origin
    with the W3C `tracecontext` propagator.
  - `local/shopper.yaml`: after each checkout the shopper opens `/chatbot/` and asks one of three
    shopping questions.
- **Why:** RUM, Session Replay and the link from a user action to its OpenTelemetry backend trace,
  with no Agent; and one browser session that covers shopping and the AI assistant (chatbot, agent,
  Claude, shop services). The shop's source and images are unchanged.
- **Notes:** the shop's own OTel browser SDK also sets `traceparent` on the same requests; which
  one wins decides which trace a RUM resource links to. To check in the RUM UI.

### 2026-10-18 · Three scenarios, each flip a Datadog change event
- **What:** `local/scenarios.yaml` now runs three non-overlapping windows each hour, UTC:
  `paymentFailure` 25% from :00 to :10, `aiRunawayAgent` on from :15 to :25, `adHighCpu` from :30
  to :45. At every flip it posts a change event (`/api/v2/events`, category `change`) on the affected
  service. `up.sh` creates the `scenarios-env` ConfigMap (env, site) and the `scenarios-dd` secret
  (API key from 1Password).
- **Why:** one problem per act of the tour, each with a quiet baseline, and the cause shown next to
  the effect: change tracking lists the flag flip on the service and as a marker on its graphs.
  Verified 23:00:17Z (`paymentFailure 25% (payment)` in change tracking).
- **Notes:** `aiRunawayAgent` on asks for 20 tool calls per prompt, past the agent's graph limit
  of 25, so some prompts end in a recursion error.

### 2026-10-18 · Load generator prompts for the agent on Claude
- **What:** `local/load-generator/locustfile.py` is the demo image's own `locustfile.py`
  (3.1.0) mounted over it from the `load-generator-locustfile` ConfigMap (`up.sh` creates it). Two
  changes, marked `datadog/local` in the file: six shopping questions replace the three prompts the
  recorded responses covered, and `user_ask_agent` no longer carries `gen_ai.input.messages`.
- **Why:** with a real model the prompts can be anything, so they now exercise the shop's tools,
  mostly `get_ads`, which ties the ad service's scenarios to the AI assistant. The attribute made the
  load generator's span the root of every Agent Observability trace, so the app was named
  `load-generator`.

### 2026-10-18 · `fd008a09` · The shop's AI agent on Claude (Haiku 5.5)
- **What:** `local/values-local.yaml` replaces the agent's `llm.py` (mounted from a ConfigMap) with the
  same `ChatLLM` class on LangChain's Anthropic client, model `claude-haiku-5-5`, recorded responses
  off (`USE_VCR=False`). The pod installs `langchain-anthropic==1.7.2` at start (the newest that fits
  the image's `langchain-core` 1.6.3). `local/up.sh` creates the `agent-llm` secret from
  `op://Employee/ddot-lab/ANTHROPIC_API_KEY`. The upstream image is unchanged.
- **Why:** Agent Observability showed no tokens or cost (`skipped_tokens_missing`) because the
  recordings carry no usage. With Claude, spans show provider `anthropic`, real tokens and
  `cost_estimate_status:success`. The native client was chosen over an OpenAI-compatible endpoint so
  the provider is recorded as Anthropic. The `aiSlowResponse` flag still applies.
- **Notes:** each call shows as the LangChain step and as the Anthropic SDK's own OTel span
  (`com.anthropic.sdk.python`). The LLM app name comes out as `load-generator`, the trace's root
  service; to be set to the shop assistant. Verified 22:47Z.

### 2026-10-18 · Planned: re:Invent feature tour (`TOUR-PLAN.md`)
- **What:** the plan for the next changes: clean-ups that show in screenshots, the DDOT SDK on
  `ad` and `recommendation`, RUM with the Datadog Browser SDK, a real Claude model behind the agent,
  change events and stage mode, a presenter dashboard and SLO from git, and an optional Agent for the
  "full value" slides.
- **Why:** screenshots for the re:Invent deck and a 15-minute tour of Datadog on OpenTelemetry data
  with DDOT components only. Nothing in it is applied yet; each step gets its own entry when it is.

### 2026-10-18 · `fc642ea5` · Datadog monitors and log index from git
- **What:** `local/datadog/` holds a monitor and a log index as templates on
  `${ENV_NAME}`; `local/dd-apply.py` creates or updates them, and `local/up.sh`
  runs it.
  - Monitor: ad service p95 latency anomaly (`basic`, 3 bounds, above, 3-minute
    window, 80% threshold, no notification targets).
  - Log index: one per env, app services only, 7 days, 1M a day, first in the
    index order.
- **Why:** so the Datadog side is rebuilt from git in any env or org instead of
  by hand. The log index replaces the `ddot-lab` filter edit above.
- **Notes:**
  - The monitor first existed by hand (id 334059057), and `dd-apply.py` adopted
    it by name.
  - `basic` adapts to a new level within about 4 minutes, so the alert window
    is 3 minutes (5 minutes at 100% missed the 20:30Z run). It alerts at onset
    and recovers while latency is still high.
  - `agile` and `robust` need more history than a new cluster has.

### 2026-10-18 · `4cd12436` · Problem scenarios on a clock; ad CPU limit
- **What:** `local/scenarios.yaml` is a pod that holds flags to a schedule
  through flagd-ui's API (`adHighCpu` on from :30 to :45 each hour, UTC).
  `local/values-local.yaml` gives ad a 300m CPU limit.
- **Why:**
  - Flags had been flipped by hand with `kubectl exec`, with no record and no
    baseline. Upstream's flagd-ui scheduler picks flags at random and keeps its
    settings only in memory.
  - With no CPU limit, `adHighCpu` used spare cores and GetAds stayed at a few
    ms. With 300m, the JVM is throttled and p95 goes from about 2.7 ms to about
    100 ms.

### 2026-10-18 · `5096449d` · Blog demo on GKE, host profiler, Playwright shopper
- **What:**
  - `local/up.sh` takes `local` or `gke`; the `gke` target creates cluster
    `otel-demo-blog`, env `otel-demo-gke-blog`.
  - The kube-stack Host Profiler is on for GKE.
  - `local/shopper.yaml` adds a headless Chromium that orders every 20 s.
  - The load generator exports to :4317, and Jaeger gets 1536Mi and 10,000
    traces.
  - `up.sh` sets paymentFailure 50%, cartFailure 100%, and productCatalogFailure
    for OLJCESPC7Z.
- **Why:**
  - The blog's screenshots needed profiles, and checkout traces that start at a
    browser click (`frontend-web`). The Locust load generator doesn't run the
    shop's JavaScript.
  - The chart points the load generator at :4318 while it exports gRPC, so its
    parent spans were lost.
  - Jaeger at 600Mi was OOM-killed and lost every stored trace.
  - The shipped productCatalogFailure rule returns "off" on both branches.

### 2026-10-15 · `453d8bd0` · Astronomy Shop on the OTel Operator and kube-stack with DDOT
- **What:** `local/` turns the chart's bundled Collector off. Every service
  sends to the DDOT daemon collector that the opentelemetry-examples kube-stack
  installer runs, and an overlay (`kube-stack-values.yaml`) keeps Jaeger and
  Grafana fed. OpenSearch is off.
- **Why:** the DDOT launch blog shows Jaeger and Datadog fed from the same
  DDOT Collector.

### 2026-09-30 · `601c9c7b` · Container and Kubernetes tags on spans
- **What:** every service's `OTEL_RESOURCE_ATTRIBUTES` carries
  `k8s.container.name` and `k8s.pod.uid`. `k8s_attributes` extracts
  `container.id`, and GKE nodes get `kube_cluster_name` as a host tag.
- **Why:** spans had no `container.id`, so Datadog attached no container tags,
  and filtering APM by `kube_cluster_name` matched nothing.

### 2026-09-29 · `fd955772` · Datadog deployment for the demo on GKE
- **What:**
  - `my-values-file.yml`: chart overrides adding the otlp_http exporter and the
    span_metrics connector beside the chart's Jaeger, Prometheus and OpenSearch
    pipelines, plus host metrics, cAdvisor, Postgres metrics and tagged
    container logs.
  - `cluster-collector.yaml`: a single-replica collector for Kubernetes
    Explorer, kube-state-metrics and Kafka metrics.
  - `frontend-lb.yaml`: a LoadBalancer limited to allowed CIDRs.
  - `up.sh`, `down.sh`, `status.sh`.
  - `.gitignore`: `datadog/.env` and a local backup folder.
- **Why:** to run the demo on GKE and send traces, metrics, logs and Kubernetes
  data to Datadog over OTLP, following Datadog's documented setup for a
  self-managed Collector. `/feature` is on the same URL as the shop, so the
  LoadBalancer is restricted. The kafkametrics receiver needs a single replica.
