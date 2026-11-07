# GCP discovery — account `gce-strukturunion` (org 134549734014)

Run 2026-11-04 07:25–08:00 CET (06:25–07:00 UTC) with SA `claude-cost-ops@claude-ops-gce-strukturunion`
via `gcp-ops.sh` (Cloud Asset Inventory at org scope, per-project gcloud listings, Monitoring API
30-day metrics, Recommender, BigQuery billing export). **Read-only; nothing was changed.**
All prices USD list price (the billing accounts bill in USD). Times Europe/Berlin unless marked UTC.

## 0. Headline

| | |
|---|---|
| Projects known | **24**: 17 in the org (16 pre-existing + `claude-ops-gce-strukturunion` created today), 4 Apps-Script system projects in folder `473398883709`, `api-project-531243544567` outside the org, 2 unreachable (`imperial-terra-205507`, `fluent-buckeye-205507`, closed BA `0032D4`) |
| Estimated run-rate, whole account | **≈ $75–110 / month** (006404 ≈ $50–55 measured; 01B7AE ≈ $20–45 estimated; 01D678 ≈ $2–3 estimated) |
| Addressable with the proposals below | **≈ $45–55 / month** — about half; the value is as much hygiene + attack surface as money |
| Biggest single items | `dockerland-2018` VM running since Jan 2021 (~$30/mo, **78 % CPU for 30 days — needs a look**), `stu-serverless` 128 GB of old container images (~$10–13/mo), toolbox Artifact Registry 30 GB (~$3/mo) |
| 12-month history | **Not available by API.** The Cloud Billing API has no cost-history endpoint; the BigQuery export holds a 2-day sliver (2026-09-30 → 2026-10-02) for 006404 and nothing yet for the other two (continuous from today). The 12-month numbers live only in the console: [006404 invoices](https://console.cloud.google.com/billing/006404-E97FEA-AEE3E8/documents) · [01B7AE invoices](https://console.cloud.google.com/billing/01B7AE-4C9C58-226EFD/documents) · [01D678 invoices](https://console.cloud.google.com/billing/01D678-3F25F0-2D70DA/documents) (Reports page of each account gives the per-project / per-service breakdown). |

## 1. Projects — what runs, last activity, owner, cost

Legend: **cost** = measured from the export where available (006404, 1.6 days → monthly), otherwise
list-price estimate from the inventory. **Last activity** = newest of: Cloud Run deploy, log entry
(90 d), resource change (Asset Inventory `updateTime`), Monitoring traffic.

### Billing account 006404-E97FEA-AEE3E8 — "RKto manuel.weisbender@strukturunion.de" (≈ $50–55/mo measured)

| Project | What runs | Last activity | Owner | ≈ $/mo | Verdict |
|---|---|---|---|---|---|
| `ipx-server` (2017) | **Cloud SQL `strukturunion-mysql`** — MySQL 8.0.40, `db-f1-micro`, 15 GB PD_HDD, zonal, `europe-west2` (UK, owner-approved per `cloud-sql-hardening.md`), 7 backups kept, public IP 35.197.202.133; 1 disk snapshot. No VMs. 30 d mean: 13.4 connections, 9 % CPU | today (cloudsql logs) | manuel | **11** (measured) | **RETAIN — toolbox production DB** (prod `toolbox` + `toolbox_staging` databases) |
| `dockerland-2018` (2018) | **VM `dockerhost-worker-europe-west1b`** e2-medium RUNNING, 60 GB pd-standard, static IP 35.233.16.50, started 2021-01-16 05:00 CET, **mean CPU 78 % over 30 d, 2.9 GB inbound/30 d**; logs show only host-maintenance migrations. App Engine app (2 versions), Firestore DB, Firebase project + auth, 8 buckets (`sql-srv-backups` ARCHIVE updated 2025-05, laravel-www-strukturunion-de, cloudrun-wordpress-manukimas-handbook, appspot/cloudbuild/artifacts buckets 2020–21), 1 machine image, 1 snapshot. 53 APIs enabled | 2026-10-14 (host maintenance); no app logs | manuel; **editor `martha.weisbender@gmail.com`**; owners also `853946848618-compute@…` + `vision-api@…` SAs | **≈ 30** (measured 1.0/day) | **CONFIRM** — what does the VM do? 78 % CPU on a 2021 box with no application logs is either a real always-on job or a compromised host. Look (serial console / SSH) before deciding; if unneeded: stop → snapshot → delete (≈ $30/mo) |
| `stu-serverless` (2020) | **28 Cloud Run services** (all min-instances 0, deploys 2020–2026), 14 buckets, 1 Cloud Function (`makeJobDirectories`, us-central1, 2024), **5 Artifact Registry repos incl. `gcr.io` = 128.27 GB / 418 images**, 8 API keys, monitoring dashboard, 44 APIs. Real traffic only on `manukimas-handbook-wp` (deployed 2026-10-20, UptimeRobot + humans), `julius-arts-rapidweaver` (UptimeRobot + `strukturunion-forwarder-watch`), `jg-ffm-veranstaltungen-prod` (UptimeRobot). `interbase-connector`, `legacy-interbase-connector`, `strukturunion-legacy-kontoimport`, `lrv-vue-backoffice-prod` get **exactly 43 200 req/30 d = one ping per minute from the Apps-Script "CloudRun-KeepAlive-by-ChatGPT"** — no human traffic. The other 21 see only scanners (Censys, ClaudeBot, InternetMeasurement) and 404s | today (keep-alive) / real: 2026-10-20 | manuel; owner also `853946848618-compute@…` SA | **≈ 13** (AR 9, storage 2, run 2) | **CONFIRM per service** — 3 keep, 4 "keep-alive only" to decide (does the toolbox still call the interbase connectors / kontoimport?), 21 look dead (templates, xmas-cards-2022, halloween-2020, wordpress-empty, zwiftbot, smarthome, gdrive-streamer, curamos (502s), prognose, old backoffices/tests, idx-laravel, cloudrun-app-*). Deleting dead services → their images → most of the 128 GB (≈ $9–12/mo) + a lot of public Laravel/WordPress attack surface |
| `strukturunion-toolbox-cloudrun` (2025) | **The naming-trap project.** 1 Cloud Run service in `europe-north1`, last deploy 2025-09-15 by `github-actions-deployer@…`, **0 requests in 30 d**, 2 images (0.07 GB), cloudbuild bucket, 38 APIs | 2025-11-10 (resource change), no logs 90 d | manuel | ≈ 0 | **SAFE to shut down** after one check that no external GitHub workflow still targets it (this repo's workflows deploy only to `cloudrun-strukturunion-toolbox`). Removes the trap |
| `core-machines` (2018) | App Engine app, Firestore DB, 5 Pub/Sub topics, API key; **no VMs**, 51 APIs (Maps, GKE, Cloud Build…) | 2025-07-18 (resource), no logs 90 d | manuel; owner also `853946848618-compute@…` SA | ≈ 0 | **CONFIRM** — looks dormant; Firestore data may matter (export before shutdown) |
| `spec-kit-vue-widget` (2025) | nothing (default APIs only) | none | manuel | 0 | **SAFE** — shut down (Recommender: "low activity, clean up") |
| `zugferd-invoice-processing` (2025) | nothing (Vertex/GenLang APIs enabled, no resources) | none | manuel | 0 | **SAFE** — shut down (Recommender: clean up) |
| `strukturunion-below-deck-app` (2024) | 1 API key, nothing else | 2024-05-25 | manuel | 0 | **SAFE** — shut down (Recommender: clean up) |
| `api-project-531243544567` (2015, outside org) | Apps-Script project "GmailLabelerExtender" (gmail + aiplatform APIs), Cloud Logging only | today (Apps-Script logs) | manuel | 0 | **RETAIN** — live Apps Script |
| `claude-ops-gce-strukturunion` (today) | BigQuery `billing_export` (2 tables), 30 APIs | today | manuel | ≈ 0 | RETAIN — ops project |

### Billing account 01B7AE-4C9C58-226EFD — "strukturunion billing account" (≈ $20–45/mo estimated; export from today)

| Project | What runs | Last activity | Owner | ≈ $/mo | Verdict |
|---|---|---|---|---|---|
| `cloudrun-strukturunion-toolbox` (2026-06) | **Toolbox production**: Cloud Run `toolbox` (128 k req/30 d, 1 vCPU/1 GiB, min 0, max 20), `toolbox-staging` (15 k), `forwarder-edge` (536 k), jobs `toolbox-migrate` / `toolbox-staging-migrate`, **Artifact Registry `toolbox` europe-west1 = 30.29 GB / 237 toolbox digests (201 tagged, 36 untagged) + orphan repo `toolbox` europe-west3 (1 image, 2026-06-24)**, 21 secrets / 34 versions, 4 Cloud Tasks queues, 27 domain mappings, Scheduler, BigQuery export dataset, 43 APIs | today | manuel | ≈ 10–25 (Run 5–15, AR 3, secrets 2, rest free tier) | **RETAIN** — see §3 proposals for AR cleanup + secret versions |
| `dekorfabrik-website` (2026-07) | Cloud Run `dekorfabrik` (362 k req/30 d) + `dekorfabrik-staging` (15 k), AR 0.4 GB, 1 secret | 2026-07-23 deploy; traffic today | manuel | ≈ 3–8 | RETAIN |
| `strukturunion-website` (2026-07) | Cloud Run `strukturunion` (363 k req/30 d, deploy 2026-10-06) + `-staging` (11 k), AR 0.38 GB, 1 secret | today | manuel | ≈ 3–8 | RETAIN |
| `earnest-vent-487414-q1` "clawdia-notion-google-ingestor" (2026-02) | nothing (Drive API enabled, no resources) | none | manuel | 0 | **CONFIRM** — probably an OAuth-client-only project (Drive ingestor); if the client is still used, keep |
| `manu-macbook-hermes-agent` (2026-06) | nothing (Gmail API enabled, no resources) | none | manuel | 0 | **CONFIRM** — same pattern (OAuth client for a local agent?) |

### Billing account 01D678-3F25F0-2D70DA — "strukturunion Customer Projects Billing" (≈ $2–3/mo estimated)

| Project | What runs | Last activity | Owner | ≈ $/mo | Verdict |
|---|---|---|---|---|---|
| `prakti-app` (2026-07) | Cloud Run `prakti-web-staging` only (3.5 k req/30 d, last deploy 2026-10-03), jobs `prakti-migrate-staging`/`prakti-seed-demo`, **AR `prakti` 10.85 GB / 90 images**, 5 secrets, 1 export bucket, BigQuery billing export (EU) | 2026-10-03 deploy; today (export) | manuel | ≈ 2–3 | RETAIN (customer project) — AR cleanup policy same as toolbox (≈ $1/mo) |

### No billing account

| Project | What | Verdict |
|---|---|---|
| `gen-lang-client-0530744678` "Nano Banana Test" (2025-10) | 1 API key (Generative Language); **owner `sarah.oels@strukturunion.de`**; Recommender: low activity | **SAFE** — shut down after a word with Sarah (API key dies with it) |
| `stu-serverless-g-1603907952279` "stu-serverless-gmail" (2020) | Gmail API only, no resources; Recommender: low activity | **SAFE** — shut down |
| `sys-67289019728751747116436941` "CloudRun-KeepAlive-by-ChatGPT" (2023) | Apps-Script system project; **this is the script pinging 4 `stu-serverless` services every minute** (logs today) | **CONFIRM** — Workspace-managed (cannot be deleted from GCP; disable the trigger in script.google.com). Cost < $1/mo but it masks every idle signal |
| `sys-02703480625400764095561968` "Website-Healthcheck-by-ChatGPT" (2023), `sys-39185190675718940785818353` + `sys-72727052724739829346758577` "Gmail to Notion" (2025-10) | Apps-Script system projects, no logs 90 d | RETAIN / ignore — $0, managed by Workspace |

### Unreachable (listed as such, nothing to do)

`imperial-terra-205507`, `fluent-buckeye-205507` — closed billing account `0032D4-604121-C75402`; the SA has no rights, `projects describe` → permission denied. Accepted.

## 2. Cross-cutting findings

1. **Security / IAM** (`iam.securityReviewer` view): the Compute default SA of `dockerland-2018` (`853946848618-compute@developer.gserviceaccount.com`) is **project Owner** on `core-machines`, `dockerland-2018` and `stu-serverless`; `vision-api@dockerland-2018` is Owner on `dockerland-2018`; an external Gmail account (`martha.weisbender@gmail.com`) is Editor on `dockerland-2018`. Default-SA-as-owner across projects means one compromised VM owns three projects — combine with the 78 % CPU VM above.
2. **Keep-alive masking**: the Apps-Script pinger makes 4 dead services look "active" (43 200 req/month each). Any future idle analysis has to filter `Google-Apps-Script` user agents; the wrapper's inventory can't see this — the Monitoring + logs check in this run did.
3. **GKE: none anywhere. Compute: one VM in the whole account.** Everything else is serverless, so idle cost is dominated by storage (images, buckets, backups), not compute.
4. **Container images are the recurring cost nobody sees**: 128 GB (`stu-serverless` gcr.io), 30 GB (toolbox), 11 GB (prakti) — ≈ $17/mo at AR rates, growing with every deploy; no repo has a cleanup policy (`cleanupPolicies` = 0 everywhere; two repos have `dryRun=true` with no policies).
5. **Billing export gap**: `006404` export shows `last_export 2026-10-02 23:56` — it stopped after two days last time. Verify tomorrow that today's re-enable is landing in all three datasets (`gcp-ops.sh costs gce-strukturunion 2026-11`).
6. **Quota-project APIs**: `sqladmin.googleapis.com` and `billingbudgets.googleapis.com` are not enabled on `claude-ops-gce-strukturunion`, so `gcloud sql instances list` and `gcp-ops.sh budgets` fail through the SA (Cloud SQL details above came from Asset Inventory instead). Proposal P-1 below.

## 3. Proposals (nothing runs without "go")

Destructive items are marked **D** — each needs its own confirmation even after a batch "go".

### P-1 — enable two APIs on the ops project (hygiene, $0)
Resources: `claude-ops-gce-strukturunion` only.
```
gcloud services enable sqladmin.googleapis.com billingbudgets.googleapis.com --project claude-ops-gce-strukturunion
```
Effect: `gcloud sql …` and `gcp-ops.sh budgets` work through the SA. Rollback: `gcloud services disable …`. **D: no.**

### P-2 — Artifact Registry cleanup policy, toolbox repo (≈ $2.5/mo, hygiene) — the re-verified 2026-10-03 finding
Re-verification 2026-11-04: production `toolbox` serves `sha256:b9e60791…` = tag `ac0ad08` (revision `toolbox-00056-2tq`, deployed 2026-10-23 18:19 CEST); staging serves `sha256:8ade8e6c…` = tag `6b446d5`; `forwarder-edge` serves `sha256:003362c1…` = tag `e2ea619`; both migrate jobs reference tagged images. **The untagged digest `sha256:719a02c3…` (2026-09-21) is no longer served by anything** — the re-tag step from the October report is moot; it is now one of **36 untagged digests** (was 6). 201 tagged digests, 30.29 GB, growing ~1 image per deploy.
Resources: `europe-west1-docker.pkg.dev/cloudrun-strukturunion-toolbox/toolbox`.
Policy (keep the last 30 tagged versions per package — enough for any rollback of a Cloud Run revision that still exists; delete untagged digests older than 7 days):
```
cat > /tmp/ar-policy.json <<'JSON'
[
  {"name": "keep-recent-30", "action": {"type": "Keep"},
   "mostRecentVersions": {"keepCount": 30}},
  {"name": "delete-untagged-7d", "action": {"type": "Delete"},
   "condition": {"tagState": "UNTAGGED", "olderThan": "604800s"}},
  {"name": "delete-tagged-older-90d", "action": {"type": "Delete"},
   "condition": {"tagState": "TAGGED", "olderThan": "7776000s"}}
]
JSON
# step 1 — dry run (reversible, deletes nothing; the registry logs what it WOULD delete):
gcloud artifacts repositories set-cleanup-policies toolbox --project cloudrun-strukturunion-toolbox \
  --location europe-west1 --policy /tmp/ar-policy.json --dry-run
# step 2 (D, separate go, after reading the dry-run log and confirming the 3 served digests are in the keep set):
gcloud artifacts repositories set-cleanup-policies toolbox --project cloudrun-strukturunion-toolbox \
  --location europe-west1 --policy /tmp/ar-policy.json --no-dry-run
```
Effect: repo shrinks to ≈ 4–6 GB (≈ $2.5/mo saved, stops the growth). Rollback: `--dry-run` again or `delete-cleanup-policies`; deleted images are not recoverable (D for step 2). Same policy for `prakti` (10.85 GB → ≈ $1/mo) and `dekorfabrik` / `strukturunion` (tiny, hygiene) as P-2b/c with their own go.

### P-3 — delete the orphan `toolbox` repo in europe-west3 (D, $0.01/mo, hygiene)
1 image (`0dd0415`, 2026-06-24), never referenced by a service or job.
```
gcloud artifacts repositories delete toolbox --project cloudrun-strukturunion-toolbox --location europe-west3
```
Rollback: none (image gone) — it is a 4-month-old build nobody serves. **D: yes.**

### P-4 — superseded Secret Manager versions (re-verified: 14, was 13) (≈ $0.84/mo, hygiene)
All three services read every secret as `latest`; the older versions are referenced by nothing. 14 enabled non-latest versions across `oidc-client-secret` (v1–4), `su-db-password` (v1), `su-mistral-key` (v1), `su-qonto-api-key` (v1–2), `su-staging-paypal-client-secret` (v1–2), `su-staging-qonto-api-key` (v1–2), `su-workos-client-secret` (v2; v1 already destroyed).
```
# step 1 — disable (reversible with `enable`); wait one deploy cycle:
for s in oidc-client-secret:1,2,3,4 su-db-password:1 su-mistral-key:1 su-qonto-api-key:1,2 \
         su-staging-paypal-client-secret:1,2 su-staging-qonto-api-key:1,2 su-workos-client-secret:2; do
  name="${s%%:*}"
  for v in $(printf '%s' "${s#*:}" | tr ',' ' '); do
    gcloud secrets versions disable "$v" --secret "$name" --project cloudrun-strukturunion-toolbox
  done
done
# step 2 (D, separate go, ≥ 7 days later): same loop with `destroy`
```
Rollback: step 1 `gcloud secrets versions enable`; step 2 none. **D: step 2.**

### P-5 — shut down the empty / dead projects (reversible for 30 days, $0 today, hygiene + fewer owners-of-nothing)
`spec-kit-vue-widget`, `zugferd-invoice-processing`, `strukturunion-below-deck-app`, `stu-serverless-g-1603907952279`, `gen-lang-client-0530744678` (after a word with Sarah), `strukturunion-toolbox-cloudrun` (after the "no external workflow deploys there" check).
```
gcloud projects delete <project-id>      # 30-day soft delete; `gcloud projects undelete` restores
```
**D: yes, each one individually** (it is reversible for 30 days, but it is still a delete).

### P-6 — `dockerland-2018` VM (≈ $30/mo) — CONFIRM first, no commands yet
Step 0 is yours: tell me what `dockerhost-worker-europe-west1b` is supposed to run. If nothing: proposal will be stop → machine image (already exists from 2021? verify date) → delete instance + disk + release static IP (D). If something: the 78 % CPU and the default-SA-is-owner finding still deserve a look.

### P-7 — `stu-serverless` service triage — CONFIRM first
I will send a per-service list (28 rows: last deploy, traffic source, image size, buckets) for a keep/delete mark-up. After mark-up: delete services (D, each), then their images (P-2-style policy on `gcr.io`), then orphan buckets (D, each). Expected ≈ $10–14/mo + 20+ public endpoints gone. Also: disable the KeepAlive Apps-Script trigger (script.google.com; not a GCP command).

### Not proposed
`ipx-server` Cloud SQL: production, leave it; `db-f1-micro` is below the Cloud SQL SLA tier and PITR is off — a *reliability* topic for another day, not a cost one. Cloud Run min-instances are 0 everywhere — nothing to downsize. UK region is a documented owner decision.

## 4. Savings summary

| Bucket | $/mo | Items |
|---|---|---|
| **Safe** (reversible / hygiene) | ≈ 4 | P-1, P-2 (toolbox + prakti), P-3, P-4, P-5 |
| **Confirm** (needs your knowledge) | ≈ 40–45 | P-6 VM (~30), P-7 stu-serverless images + buckets (~10–14), core-machines / OAuth-only projects (0) |
| **Retain** | — | toolbox prod + DB, both websites, prakti, api-project, ops project, sys-* |

## 5. Still open / caveats
- 12-month per-project costs: console only (links in §0). Export continuity: check tomorrow.
- Cost figures for 01B7AE / 01D678 are inventory estimates until the export has a full month.
- `gcloud organizations list` returns nothing for the SA (`roles/editor` lacks `resourcemanager.organizations.get`); everything above used org-scoped Asset Inventory instead. Optional: `roles/resourcemanager.organizationViewer`.
- The env secret is currently named `CP_COST_OPS_KEY_GCE_STRUKTURUNION` (missing the leading `G`) — the merged hook will not pick it up until it is renamed to `GCP_COST_OPS_KEY_GCE_STRUKTURUNION` in the web environment settings. This session activated the config manually.
