# GCP ops log — every executed change, dated

Append-only. One line per change that reached live Google Cloud infrastructure
through a Claude Code session, written **when it ran**, not when it was planned
(see CLAUDE.md § Conventions: a runbook block that mutates live infrastructure is
not done until a dated line says it ran). Proposals that were not executed do not
belong here; they live in the session / PR that made them.

Format (`gcp-ops log <alias> "<text>"` appends it):

```
- YYYY-MM-DD HH:MM CET|CEST (Claude|Manuel, <account alias>): P-<n> — what ran, on which resources, result
```

Contract: discovery is free; every change is a written proposal (commands,
resources, cost effect, rollback) executed only after an explicit "go";
destructive acts (delete, destroy secret versions, unlink billing, disable APIs,
downsize production) are confirmed individually even inside an approved batch.
Details: `.claude/skills/gcloud-cost-ops/SKILL.md`.

## Log

- 2026-11-04 07:35 CET (Claude, gce-strukturunion): cost-ops SA activated as gcloud configuration `ops-gce-strukturunion` in-session (TBX-307) — no infrastructure changed; verification only (`billing accounts list`, org-scoped asset search).
- 2026-11-04 09:17 CET (Claude, gce-mdbx): cost-ops SA activated as gcloud configuration ops-gce-mdbx in-session (TBX-309) at 07:56 — no infrastructure changed; verification only (billing accounts list, org-scoped asset search).
- 2026-11-04 09:17 CET (Claude, gce-mdbx): A (go 09:15) — enabled billingbudgets.googleapis.com on claude-ops-gce-mdbx (09:16). Rollback: gcloud services disable billingbudgets.googleapis.com --project=claude-ops-gce-mdbx.
- 2026-11-04 09:17 CET (Claude, gce-mdbx): A (go 09:15) — created budget 'gce-mdbx monthly guardrail' 1d68f4a2-33ef-4e40-919d-9b452b78c8d5 on billing account 010E7E-C918EB-0E7DBD: 40 EUR/month, thresholds 50/90/100 % actual + 100 % forecast, default e-mail to billing admins/users (09:16). Cost effect: none. Rollback: gcloud billing budgets delete 1d68f4a2-33ef-4e40-919d-9b452b78c8d5 --billing-account=010E7E-C918EB-0E7DBD.
- 2026-11-04 09:17 CET (Claude, gce-mdbx): comfy-ui-ltx (go 09:15: 'delete the full project without backup', supersedes C1) — gcloud projects delete comfy-ui-ltx DENIED for the SA (editor lacks resourcemanager.projects.delete); instead deleted VM comfy-l4 (g2-standard-8 + L4, us-central1-a) with both disks (comfy-l4 100 GiB, comfy-data 150 GiB pd-balanced) and snapshot comfy-data-pre-klein-20260604 (09:17). Project left ACTIVE and empty — shutdown by admin@md-bx.de pending. Cost effect: -24.66 EUR/month. Rollback: none (no backup, by decision).
- 2026-11-04 09:39 CET (Manuel, gce-mdbx): comfy-ui-ltx shut down from the console as admin@md-bx.de (between the owner grant and 09:38) — recorded by Claude, who found the project already DELETE_REQUESTED and unlinked from billing account 010E7E-C918EB-0E7DBD when running the agreed shutdown; the SA's own 'gcloud projects delete' was denied (policy of a project in deletion is not readable). 30-day restore window: gcloud projects undelete comfy-ui-ltx. Cost effect: none beyond the 09:17 deletions (project was empty).
