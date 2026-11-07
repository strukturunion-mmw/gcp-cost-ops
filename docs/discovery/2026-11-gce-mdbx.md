# GCP discovery — account `gce-mdbx` (org 526430919328, md-bx.de) — 2026-11-04

Ticket: **TBX-309** · companion to TBX-307 (account `gce-strukturunion`, hook + skill).
Billing account: **010E7E-C918EB-0E7DBD** "Mein Rechnungskonto" (EUR, open, parent = the org).
Invoice documents: <https://console.cloud.google.com/billing/010E7E-C918EB-0E7DBD/documents>
— **last charge: October 2026 usage, 25,01 € (collected 1 Nov 2026, Mastercard ••8024).**

All times Europe/Berlin. Discovery run 07:56–08:25 (06:56–07:25 UTC) with service account
`claude-cost-ops@claude-ops-gce-mdbx.iam.gserviceaccount.com` via gcloud configuration
`ops-gce-mdbx` (default configuration unchanged: `toolbox-logreader`).

## 1. Access verification

| Check | Result |
|---|---|
| `gcloud organizations list` | **0 items** — the SA lacks `resourcemanager.organizations.get` (none of editor / cloudasset.viewer / securityReviewer carry it). Everything else works; see proposal B. |
| `gcloud organizations get-iam-policy 526430919328` | OK (securityReviewer) — SA roles confirmed: artifactregistry.admin, cloudasset.viewer, editor, iam.securityReviewer, recommender.viewer, secretmanager.secretVersionManager, serviceusage.serviceUsageAdmin |
| `gcloud billing accounts list` | 010E7E-C918EB-0E7DBD, open; SA + admin@md-bx.de are billing.admin |
| `gcloud billing projects list` | all 5 projects linked, billing enabled |
| `gcloud asset search-all-resources --scope=organizations/526430919328` | OK — 603 assets exported |

## 2. Billing export (dataset `claude-ops-gce-mdbx.billing_export`, EU, created 2026-11-04 07:59)

| Export | Evidence | Status |
|---|---|---|
| Pricing | `bq ls --transfer_config --transfer_location=eu` → "Pricing BigQuery Transfer" (`transferConfigs/6aed6a6a-…`) | **configured** |
| Standard usage cost | table `gcp_billing_export_v1_010E7E_C918EB_0E7DBD` | **not yet visible** — `bq ls billing_export` is empty |
| Detailed usage cost | table `gcp_billing_export_resource_v1_010E7E_C918EB_0E7DBD` | **not yet visible** |

Only the pricing export creates a transfer config; the standard and detailed exports have no API
surface and show up as tables after the first daily run, which can take up to 24 h (often 2–6 h)
after enabling. Nothing can be verified before then. **If both tables are still missing on
2026-11-05 after 12:00**, re-enable in the console: Billing → select
*Mein Rechnungskonto* → **Billing export** → tab **BigQuery export** → *Standard usage cost* →
**Edit settings** → project `claude-ops-gce-mdbx`, dataset `billing_export` → **Save**; repeat for
*Detailed usage cost*. Direct link: <https://console.cloud.google.com/billing/010E7E-C918EB-0E7DBD/export>.
Re-check with `bq ls claude-ops-gce-mdbx:billing_export`.

## 3. Cost history — last 12 months

No export history and no cost API exist, so the monthly totals come from the Google Payments
"Zahlung erhalten" notices to admin@md-bx.de (each 1st-of-month charge = previous month's invoice).

| Usage month | Charged | Amount | Note |
|---|---|---|---|
| 2025-11 | 2025-12-01 | 0,11 € | mdbx storage only |
| 2025-12 | 2026-01-01 | 0,11 € | |
| 2026-01 | 2026-02-01 | 0,11 € | |
| 2026-02 | 2026-03-01 | 0,11 € | |
| 2026-03 | 2026-04-01 | 0,11 € | |
| 2026-04 | 2026-05-02 | 0,11 € | 1 May: payment **declined** on card ••9638, re-collected 2 May on ••8024 |
| 2026-05 | 2026-06-01 | 0,76 € | comfy-ui-ltx created 31 May |
| 2026-06 | 2026-07-01 | 27,30 € | GPU VM ran until 5 Jun, then disks only |
| 2026-07 | 2026-08-01 | 24,00 € | |
| 2026-08 | 2026-09-01 | 25,66 € | |
| 2026-09 | 2026-10-01 | 24,23 € | |
| 2026-10 | 2026-11-01 | 25,01 € | |
| **12 months** | | **127,62 €** | |

**Attribution (bottom-up, EUR list prices from the Cloud Billing Catalog, us-central1):**

| Project | Service | Monthly | Basis |
|---|---|---|---|
| comfy-ui-ltx | Compute: 2 × pd-balanced (100 + 150 GiB) | 22,45 € | 250 GiB × 0,0898 €/GiB-mo |
| comfy-ui-ltx | Compute: snapshot `comfy-data-pre-klein-20260604` (49,3 GiB) | 2,21 € | × 0,0449 €/GiB-mo |
| comfy-ui-ltx | Compute: VM `comfy-l4` (g2-standard-8 + 1 × L4) | **0 €** (TERMINATED) | would be 0,77 €/h ≈ 559 €/mo if left running |
| mdbx-clips-collection | Storage: 4,75 GiB (container images, US multi-region) + Cloud Run within free tier | ≈ 0,11 € | matches the pre-June invoices |
| n8n-sheets-integration-476215 | — | 0 € | no billable resources |
| ninth-glider-223712 | — | 0 € | no billable resources |
| claude-ops-gce-mdbx | BigQuery export dataset (empty) | 0 € | |
| **Run-rate** | | **≈ 24,8 €/mo** | invoices 24,00–25,66 € confirm it |

**~99 % of the bill is the stopped GPU workstation's disks.**

## 4. Inventory and activity per project

### comfy-ui-ltx (794443177538, created 2026-05-31, owner admin@md-bx.de)
- **VM `comfy-l4`** us-central1-a, g2-standard-8, 1 × NVIDIA L4, STANDARD provisioning,
  **TERMINATED** since 2026-06-05 04:06 PDT (last start 03:00 PDT the same day). Ephemeral
  external IP (released while stopped). No static IPs, no snapshot schedule, no Backup & DR vaults.
- **Disks:** `comfy-l4` boot 100 GiB pd-balanced; `comfy-data` 150 GiB pd-balanced — both attached.
- **Snapshot:** `comfy-data-pre-klein-20260604` (150 GiB disk, 52,9 GB stored, 2026-06-04).
  Taken *before* the final session on 5 Jun, so it does not contain changes from that session.
- Quota preferences requested: `a100-gpus-uc1-1`, `a2-cpus-uc1-12`, `gpus-all-regions-1`.
- APIs: compute, storage, BigQuery family, backupdr, oslogin, monitoring … (28). No buckets, no BQ datasets.
- Activity: no workload logs in 30 d; audit log shows `ServiceUsage.UpdateConsumerPolicy` on
  2026-10-29 20:31 (someone enabled/disabled an API in the console).
- Recommender: "considerable activity but **no active owner**" (projectUtilization); 1 unused
  IAM role binding; default compute SA inactive.

### mdbx-clips-collection (727973635797, created 2020-05-06, owners admin@md-bx.de + manuel.weisbender@strukturunion.de)
- **Cloud Run `cs-mdbx-mediabox-website-prod`** us-central1, minScale 0, 1 CPU / 512 MiB, latest
  revision 2023-07-02, image `gcr.io/mdbx-clips-collection/cloudrun-mdbx-gallery`.
  **Live: domain mappings `md-bx.de` and `app.md-bx.de` → prod (Ready, cert provisioned).**
  Traffic last 30 d: ~1 300–2 000 requests/day — 70 % are 404 scans (`/wp-login.php` etc.),
  23 % 302, 6 % 200. Real but small; stays inside the Cloud Run free tier.
- **Cloud Run `cs-mdbx-mediabox-website-test`** — same config, **0 requests in 30 d**, latest revision 2023-07-02. Costs 0 € (minScale 0).
- 16 revisions retained (free).
- **Cloud Function `moveGcsToGdriveSpecific`** gen 1, **nodejs10 (runtime decommissioned)**, HTTP
  trigger, 256 MB, last deployed 2020-05-20, SA = App Engine default. **0 executions in 30 d.**
- **Buckets:** `artifacts.mdbx-clips-collection.appspot.com` 4,75 GiB / 430 objects (Container
  Registry image layers, newest 2023-07-02); `mdbx-clips-collection_cloudbuild` 2 objects (2023);
  `mdbx-clips-covers` 1 object (2020); `mdbx-clips-upload-staging` empty.
- **Artifact Registry:** gcr.io-mirror repos `gcr.io`, `asia.gcr.io`, `eu.gcr.io`, `us.gcr.io` — all 0 MB
  (created 2023-06-08 by the Container Registry transition).
- Service accounts: 6 (prod, test, app-worker, gdrive, compute default, appspot default).
  **User-managed keys:** `app-worker` (2020-05-14), `gdrive` (2020-05-06). Recommender: all 6 SAs
  inactive in the last 90 d, 7 role bindings with 0 permissions used.
- 1 API key ("API-Schlüssel 1", 2023-06-08). No SQL, GKE, Scheduler, secrets.
- APIs: run, cloudfunctions, cloudbuild, artifactregistry, containerregistry, pubsub, drive, … (25).

### n8n-sheets-integration-476215 (680200184431, created 2025-10-25, owner admin@md-bx.de)
- **No resources** besides the auto-created `default` VPC (2026-05-31), no buckets, no BQ datasets,
  no SA keys. APIs enabled: sheets, drive, compute, BigQuery family … (26).
- No logs in 30 d. Recommender: "**low activity — recommend cleaning up**".
- Likely holds the **OAuth client** used by an n8n Sheets workflow (OAuth clients are not visible
  through the asset or IAM APIs) — shutting the project down would revoke those tokens.

### ninth-glider-223712 "My First Project" (4201555069, created 2018-11-26, owner admin@md-bx.de)
- **No resources** besides the `default` VPC (2026-05-31). One API key from 2019-06-21, one
  user-managed key on the default compute SA from 2019-06-20. No logs in 30 d.
- Recommender: "**low activity — recommend cleaning up**"; 3 unused role bindings.

### claude-ops-gce-mdbx (287938816610, host project, created 2026-11-04)
- Only the cost-ops SA (+ its key, 2026-11-04) and the `billing_export` dataset. No workloads.

## 5. Flags

| Flag | Where | Severity |
|---|---|---|
| Idle paid resource: 250 GiB of disks + 1 snapshot behind a VM stopped for 5 months | comfy-ui-ltx | **cost** (24,7 €/mo) |
| Idle project (Recommender) | n8n-sheets-integration-476215, ninth-glider-223712 | hygiene (0 €) |
| Idle service: test Cloud Run service, 0 requests / 30 d | mdbx-clips-collection | hygiene (0 €) |
| Decommissioned runtime nodejs10, no invocations, deployed 2020 | mdbx function | hygiene / security |
| User-managed SA keys from 2019/2020, SAs inactive 90 d | mdbx (2), ninth-glider (1) | security |
| API keys from 2019 and 2023 | ninth-glider, mdbx | security (check restrictions) |
| Single human owner (admin@md-bx.de) on 4 of 5 projects; Recommender "no active owner" | comfy-ui-ltx | ownership |
| Payment declined 2026-05-01 (old card) | billing account | resolved, keep card ••8024 current |
| No budget on the billing account | billing account | **monitoring gap** |
| `gcloud organizations list` blind for the SA | org IAM | tooling |

## 6. Safe / confirm / retain

**Safe (no data, no traffic, zero-content or reversible):**
- S1 — delete the three empty gcr.io mirror repos `asia.gcr.io`, `eu.gcr.io`, `us.gcr.io` (0 MB). Keep `gcr.io`. Savings 0 €.
- S2 — delete the 14 non-serving Cloud Run revisions older than the serving ones (prod keeps `…-00025-fac`, test `…-00052-hes`). Savings 0 €; re-deploy from the image digest restores any.

**Confirm (destructive or affects something that might still be wanted):**
- C1 — **comfy-ui-ltx workstation**: fresh snapshots of both disks, then delete VM + disks; keep
  snapshots. **Saves ≈ 19 €/mo** (≈ 22,45 € disks − ≈ 3,5 € new snapshot storage). Deleting the
  June snapshot afterwards adds 2,21 €/mo → **≈ 21 €/mo (≈ 250 €/yr)**.
- C2 — delete Cloud Function `moveGcsToGdriveSpecific` (nodejs10, unused). 0 €, security hygiene.
- C3 — delete Cloud Run service `cs-mdbx-mediabox-website-test`. 0 €, hygiene.
- C4 — delete user-managed SA keys: `app-worker` (2020), `gdrive` (2020), ninth-glider default-compute (2019). Irreversible; 0 €.
- C5 — shut down `ninth-glider-223712` (30-day recovery window). 0 €.
- C6 — shut down `n8n-sheets-integration-476215` — **only if the n8n Sheets workflow is retired**
  (it very likely holds that workflow's OAuth client). 0 €.

**Retain:**
- `cs-mdbx-mediabox-website-prod` + domain mappings `md-bx.de`, `app.md-bx.de` (live site).
- `artifacts.mdbx-clips-collection.appspot.com` + `gcr.io` repo (the only copy of the site image for a
  redeploy; 0,11 €/mo), `mdbx-clips-covers`, `mdbx-clips-upload-staging`.
- `claude-ops-gce-mdbx` (host) and the billing export dataset.
- comfy snapshots until the user decides the ComfyUI data is no longer needed.

**Estimated savings: ≈ 21 €/mo of a 24,8 €/mo bill** (everything else is already ~0).

## 7. Budget alert proposal — billing account 010E7E-C918EB-0E7DBD

Monthly budget **40 €** (≈ 1,6 × run-rate; after C1 it is ≈ 10× the residual, so any revived GPU
usage — 0,77 €/h — trips the 50 % rule within ~26 GPU hours). Thresholds 50 / 90 / 100 % of actual
spend and 100 % of forecasted spend; e-mail to billing admins/users (admin@md-bx.de). Needs the
Budget API on the host project (non-destructive).

```bash
gcloud services enable billingbudgets.googleapis.com --project=claude-ops-gce-mdbx
gcloud billing budgets create \
  --billing-account=010E7E-C918EB-0E7DBD \
  --display-name="gce-mdbx monthly guardrail" \
  --budget-amount=40EUR --calendar-period=month \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 --threshold-rule=percent=1.0,basis=forecasted-spend
```
Rollback: `gcloud billing budgets delete <id> --billing-account=010E7E-C918EB-0E7DBD`.
Cost effect: none.

## 8. Proposals awaiting "go" (commands, cost effect, rollback)

> **Status 2026-11-04 09:20:** go given for **A**, **B** and a changed C1 ("delete the full
> comfy-ui-ltx project without backup"). Executed and logged in `gcp-ops-log.md`: A (API + budget),
> the comfy-l4 VM, both disks and the snapshot. **Not executable by the SA:** B (needs
> `resourcemanager.organizations.setIamPolicy`, i.e. an Organization Administrator) and the project
> shutdown itself (`resourcemanager.projects.delete` is in roles/owner, not editor) — both are for
> admin@md-bx.de in the console. C2–C6, S1, S2: on hold by decision.

All run under `CLOUDSDK_ACTIVE_CONFIG_NAME=ops-gce-mdbx`. Every executed step gets a dated line in
`docs/ops/gcp-ops-log.md`.

**A — Budget (section 7).** Non-destructive.

**B — Org visibility for the SA.** Non-destructive, 0 €.
```bash
gcloud organizations add-iam-policy-binding 526430919328 \
  --member=serviceAccount:claude-cost-ops@claude-ops-gce-mdbx.iam.gserviceaccount.com \
  --role=roles/resourcemanager.organizationViewer
```
Rollback: same command with `remove-iam-policy-binding`.

**C1 — comfy-ui-ltx workstation (destructive, individual confirmation).**
```bash
# 1. snapshots (non-destructive, ~3,5 €/mo while kept; use --storage-location=us for lowest price)
gcloud compute snapshots create comfy-data-final-20261104 --source-disk=comfy-data --source-disk-zone=us-central1-a --project=comfy-ui-ltx --storage-location=us
gcloud compute snapshots create comfy-l4-boot-final-20261104 --source-disk=comfy-l4 --source-disk-zone=us-central1-a --project=comfy-ui-ltx --storage-location=us
# 2. verify both READY, then delete VM + both disks   ← confirm separately
gcloud compute instances delete comfy-l4 --zone=us-central1-a --project=comfy-ui-ltx --delete-disks=all
# 3. (optional, after 2 is verified) delete the June snapshot   ← confirm separately
gcloud compute snapshots delete comfy-data-pre-klein-20260604 --project=comfy-ui-ltx
```
Cost effect: −22,45 €/mo (+ −2,21 €/mo with step 3), + ≈ 3,5 €/mo for the two new snapshots.
Rollback: `gcloud compute disks create … --source-snapshot=…` for both, then
`gcloud compute instances create comfy-l4 --machine-type=g2-standard-8 --accelerator=type=nvidia-l4,count=1 --zone=us-central1-a --disk=name=comfy-l4,boot=yes --disk=name=comfy-data --maintenance-policy=TERMINATE`.

**C2 — function.** `gcloud functions delete moveGcsToGdriveSpecific --region=us-central1 --project=mdbx-clips-collection`
Rollback: redeploy from source (not in GCP — source bucket objects date from 2020; confirm a copy exists in git first).

**C3 — test service.** `gcloud run services delete cs-mdbx-mediabox-website-test --region=us-central1 --project=mdbx-clips-collection`
Rollback: `gcloud run deploy cs-mdbx-mediabox-website-test --region=us-central1 --project=mdbx-clips-collection --image=gcr.io/mdbx-clips-collection/cloudrun-mdbx-gallery@sha256:19eefde64ae459d29f02b81f82a3925b02684467468cd4ceb8d40a1a3f392303`
(full digest of the serving test revision `cs-mdbx-mediabox-website-test-00052-hes`; the prod revision `…-00025-fac` serves
`sha256:49ae14636580b14f56a03ae0dcec8e6f9630084f38952e4d3259cf725e4db8f9`).

**C4 — SA keys.** `gcloud iam service-accounts keys delete <key-id> --iam-account=<sa>` ×3. No rollback (new key would have to be issued).

**C5 / C6 — project shutdown.** `gcloud projects delete ninth-glider-223712` (and, if confirmed, `n8n-sheets-integration-476215`).
Rollback within 30 days: `gcloud projects undelete <id>`.

**S1 — empty repos.** `gcloud artifacts repositories delete asia.gcr.io --location=asia --project=mdbx-clips-collection` (likewise `eu.gcr.io`/europe, `us.gcr.io`/us). Rollback: recreate (empty).

**S2 — old revisions.** `gcloud run revisions delete <name> --region=us-central1 --project=mdbx-clips-collection` for the 14 non-serving revisions. Rollback: redeploy by digest — the full digests are recorded with `gcloud run revisions list --project=mdbx-clips-collection --region=us-central1 --format="table(name,spec.containers[0].image)"` into the ops log before the first delete.

## 9. Method notes

- Inventory: Cloud Asset Inventory (org scope) + per-service `gcloud … list` for each project;
  commands that hit a disabled API were left disabled (no API was enabled during discovery).
- Activity: Cloud Logging (30-day `_Default` retention), Cloud Run request logs, VM
  start/stop timestamps, bucket object timestamps, Recommender/Insights (projectUtilization,
  IAM policy, service accounts). Compute idle-resource insights are not offered for this zone/API version.
- Prices: Cloud Billing Catalog API, service `6F81-5844-456A` (Compute Engine), currency EUR, 2026-11-04.
