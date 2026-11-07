---
name: gcloud-cost-ops
description: >-
  Run GCP cost-ops for every Google Cloud account a session holds a cost-ops
  service account for (today: alias gce-strukturunion — org 134549734014, three
  billing accounts). Use whenever the work is "what runs where and what does it
  cost": a project / resource inventory via Cloud Asset Inventory, monthly costs
  per billing account from the BigQuery billing exports reconciled against the
  console invoice, budgets, idle-resource findings, or any change to live GCP
  infrastructure (cleanup policies, secret versions, shutting down idle projects).
  Encodes the safeguard contract — discovery is free, every change is a written
  proposal that runs only after an explicit "go", destructive acts get individual
  confirmation, every executed change gets a dated line in docs/ops-log.md.
---

# GCP cost-ops (`gcp-ops`)

A cost-ops **service account** (`claude-cost-ops@claude-ops-<alias>.iam.gserviceaccount.com`)
exists per Google Cloud account we look after. It holds org-level `roles/editor`,
`cloudasset.viewer`, `recommender.viewer`, `iam.securityReviewer`,
`serviceusage.serviceUsageAdmin`, `secretmanager.secretVersionManager`,
`artifactregistry.admin`, the same on named projects outside the org, and
`roles/billing.admin` on the account's billing accounts. That is **far more than
read-only**, which is why the SessionStart hook activates it as its **own named
gcloud configuration `ops-<alias>`** and never as the default: nothing runs with
it unless a command opts in, and the wrapper below is the one place that does.
Operator runbook (SA, roles, env secrets, rotation):
**`docs/gcloud-cost-ops-access.md`**.

| Env | Meaning |
|---|---|
| `GCP_COST_OPS_KEY_<ALIAS>` | JSON SA key (web env secret). Alias = suffix lower-cased, `_`→`-`. |
| `GCP_COST_ACCOUNTS` | `alias:org-id:ba1,ba2,…` — several accounts separated by `;` or whitespace. |
| `accounts/<alias>.conf` | committed, non-secret: `extra_projects=` (outside the org), `unreachable_projects=`, `closed_billing_accounts=`. |

The second account will arrive through the same `claude-ops-setup.sh`; adding its
key + `GCP_COST_ACCOUNTS` entry (+ an `accounts/<alias>.conf` if it has
out-of-org projects) is the whole onboarding — no code change.

## The safeguard contract (non-negotiable)

1. **Discovery and reports are free.** Inventory, costs, budgets, recommender
   insights, IAM reads, log reads — run them whenever useful, no confirmation.
2. **Every change starts as a written proposal**: the exact commands, the
   resources touched, the cost effect, the rollback. It runs **only after an
   explicit "go"** from Manuel. A "go" covers that proposal, not the next one.
3. **Destructive acts get an individual confirmation even inside an approved
   batch** — delete anything, destroy Secret Manager versions, unlink billing,
   disable APIs, downsize production. List them one by one and wait for each.
4. **Every executed change gets a dated line in `docs/ops-log.md`**
   (`gcp-ops log <alias> "…"` appends it; commit it with the work).
5. Production is production: `ipx-server` hosts the toolbox's Cloud SQL
   instance; `cloudrun-strukturunion-toolbox` is the toolbox itself (note the
   naming trap — `strukturunion-toolbox-cloudrun` is the *old* project).

## Commands (run from the repo root)

```bash
W=.claude/skills/gcloud-cost-ops/gcp-ops.sh
$W accounts                                   # aliases, orgs, billing accounts, config state
$W auth gce-strukturunion                     # re-activate ops-<alias> if a session lost it
$W projects gce-strukturunion                 # every project: number, parent, billing account (+ the unreachable ones)
$W inventory gce-strukturunion                # Cloud Asset Inventory: counts per project × asset type + last change
$W inventory gce-strukturunion --project ipx-server          # every resource of one project
$W inventory gce-strukturunion --types run.googleapis.com/Service,sqladmin.googleapis.com/Instance
$W inventory gce-strukturunion --all --json   # raw, including noise types (services, log buckets, default network)
$W costs gce-strukturunion 2026-11            # per billing account, by service, + invoice link
$W costs gce-strukturunion 2026-11 --by project --billing-account 01B7AE-4C9C58-226EFD
$W budgets gce-strukturunion
$W run gce-strukturunion -- <any gcloud args>  # e.g. recommender / artifacts / secrets commands under ops-<alias>
$W bq  gce-strukturunion -- <any bq args>
$W log gce-strukturunion "enabled billingbudgets API on claude-ops-gce-strukturunion (proposal P-3, go 10:12)"
$W --help
```

Every call runs under `CLOUDSDK_ACTIVE_CONFIG_NAME=ops-<alias>` with an empty
`CLOUDSDK_AUTH_ACCESS_TOKEN` (the web environment's injected token has a type the
APIs reject). The default configuration — empty and unprivileged in this
repository — is never changed.

## How each report is built

**Inventory** — `gcloud asset search-all-resources` at **org scope** (one call
covers every project in the org, including ones the SA was never told about) plus
one call per `extra_projects` entry. Default output hides asset types every
project carries with no cost signal (enabled services, log buckets/sinks, default
network/firewall/routes, service accounts); `--all` shows them. The
`LAST_RESOURCE_CHANGE` column is the newest `updateTime` over a project's
assets — a cheap last-activity signal. For the real one use logs
(`$W run <alias> -- logging read 'severity>=DEFAULT' --project P --limit 1 --freshness 90d`)
and the per-service timestamps (Cloud Run last deploy, Compute
`lastStartTimestamp`, Scheduler `lastAttemptTime`).

**Costs** — one BigQuery table per billing account, found through Asset
Inventory (`bigquery.googleapis.com/Table` named `gcp_billing_export_v1_<BA>`), so
nothing about where an export lands is hard-coded. For `<YYYY-MM>` the wrapper
groups `invoice.month` by service / project / SKU (cost, credits, net per row —
tax appears as its own "Invoice" row with no project), then prints the
invoice's bottom line split the way the invoice is: `regular`, `tax`,
`adjustments`, `rounding`, `credits` and the tax-INCLUSIVE `invoice_total`,
together with the invoice link
`https://console.cloud.google.com/billing/<BA>/documents` to reconcile against
(the pre-tax subtotal is `invoice_total - tax`, i.e. regular + adjustments +
rounding + credits). **Exports have no history before they were enabled** (for
gce-strukturunion: a two-day sliver 2026-09-30 → 2026-10-02 from an earlier
attempt, continuous only from 2026-11-04). Months before that exist only as
console invoices; the Cloud Billing API has no cost-history endpoint. The
detailed (`_resource_`) table carries resource names for per-resource attribution;
the pricing export lands as `cloud_pricing_export`.

**Budgets** — `gcloud billing budgets list` per billing account. Needs
`billingbudgets.googleapis.com` enabled on the SA's quota project (the
`claude-ops-<alias>` project); enabling it is a change → proposal first.

**Idle signals** — Recommender, per project and location:
`google.compute.instance.IdleResourceRecommender`,
`google.compute.disk.IdleResourceRecommender`,
`google.cloudsql.instance.IdleRecommender`,
`google.resourcemanager.projectUtilization.Recommender` (unattended projects),
`google.billing.CostInsights.Recommender`. Plus `gcloud services list --enabled`
(an API nobody calls is a project nobody uses) and the Asset `updateTime`s above.

## Proposal → go → execute → log (how a change moves)

```
### Proposal P-<n>: <one line>
Resources: <project / resource names>
Commands:
  <exact gcloud / bq commands>
Cost effect: <€/month, or "none — hygiene">
Rollback: <how to undo, or "not reversible — individual confirmation required">
Destructive: yes/no  (yes → each item is confirmed on its own, even after a batch "go")
```

Post the proposal, wait for **"go"**. Execute exactly what was proposed (deviations
→ new proposal). Then `gcp-ops log <alias> "P-<n>: <what ran>"` and commit the log
line with the work. Times in reports are Europe/Berlin (the session clock already
is; API timestamps are UTC — convert and say so).

## Known limits

- `gcloud organizations list` returns nothing for the SA: `roles/editor` lacks
  `resourcemanager.organizations.get`. Org-scoped **asset search works**, which is
  what the inventory uses; `roles/resourcemanager.organizationViewer` would add
  the listing if ever needed.
- `gcloud projects list` does not return out-of-org projects the SA has rights
  on; that is what `extra_projects` in `accounts/<alias>.conf` is for.
- Apps-Script system projects (`sys-…`, parent folder `473398883709`) show up with
  no billing account — they are Workspace-managed and cost nothing; leave them.
