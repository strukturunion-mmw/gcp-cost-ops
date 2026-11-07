# gcp-cost-ops — project guide for Claude Code

## What this is
The ops repository for the **Google Cloud cost-ops** of two accounts: inventory, costs, budgets
and — after an explicit "go" — clean-up of live GCP infrastructure. It holds the session tooling
(hooks, skills), the operator runbook, the discovery reports and the append-only change log.
Nothing secret lives here: SA keys are web-environment secrets; billing-account and project ids
are fine to commit.

## Accounts

| Alias | Org | Workspace | SA | Billing accounts |
|---|---|---|---|---|
| `gce-strukturunion` | `134549734014` | strukturunion.de | `claude-cost-ops@claude-ops-gce-strukturunion.iam.gserviceaccount.com` | `006404-E97FEA-AEE3E8`, `01B7AE-4C9C58-226EFD`, `01D678-3F25F0-2D70DA` (+ closed `0032D4-604121-C75402`, no rights) |
| `gce-mdbx` | `526430919328` | md-bx.de | `claude-cost-ops@claude-ops-gce-mdbx.iam.gserviceaccount.com` | `010E7E-C918EB-0E7DBD` |

`gce-strukturunion` also covers `api-project-531243544567` (outside the org); `imperial-terra-205507`
and `fluent-buckeye-205507` are unreachable by decision. Both SAs hold org-level `roles/editor` +
`cloudasset.viewer` + `recommender.viewer` + `iam.securityReviewer` + `serviceusage.serviceUsageAdmin`
+ `secretmanager.secretVersionManager` + `artifactregistry.admin`, and `roles/billing.admin` on their
billing accounts. Every session runs them only through the named gcloud configuration `ops-<alias>`;
the `default` configuration stays empty and unprivileged.

## Safeguard contract (non-negotiable)
Discovery and reports are free; any change starts as a written proposal (commands, resources, cost
effect, rollback) and runs only after my explicit "go"; destructive acts (delete, destroy secret
versions, unlink billing, disable APIs, downsize production) get an individual confirmation even
inside an approved batch; every executed change gets a dated line in the ops log. Report times in
Europe/Berlin (append UTC for raw API timestamps). Production: `ipx-server` hosts the toolbox's
Cloud SQL instance; `cloudrun-strukturunion-toolbox` is the toolbox (naming trap:
`strukturunion-toolbox-cloudrun` is the old, idle project).

## Board and pull requests
- Tickets live on the Notion **"strukturunion toolbox Development Taskboard"** (`TBX-<n>`; env
  `NOTION_TOKEN`, `NOTION_BOARD_ID`; the `notion-board` skill). All work gets a ticket; **every PR
  title is `TBX-<n>: …`**. On PR open set the ticket In Review + PRUrl; after merge → Done.
- PR flow: open as **draft** → mark **ready** → **merge only after my "go"**. The Codex reviewer is
  **not set up on this repository yet**, so marking ready triggers no automated review here; CI
  does not exist yet either. Squash-merge.
- **Report times in Europe/Berlin** (CET/CEST). The SessionStart hook sets `TZ=Europe/Berlin`, so
  `date` already prints local time; a raw API timestamp (GitHub, Notion, Google APIs — all UTC) is
  quoted as Berlin local with UTC in parentheses: *"deploy finished 17:30 (15:30 UTC)"*.

## Where things are
- Skill + wrapper: `.claude/skills/gcloud-cost-ops/` (`SKILL.md`, `gcp-ops.sh`, `accounts/*.conf`)
- Board skill: `.claude/skills/notion-board/`
- Session hooks: `.claude/hooks/session-start.sh` (gcloud + `ops-<alias>` activation),
  `.claude/hooks/session-timezone.sh` (TZ) — registered in `.claude/settings.json`
- Runbook (SA, roles, secrets, rotation): `docs/gcloud-cost-ops-access.md`
- Ops log (append-only, every executed change): `docs/ops-log.md`
- Discovery reports: `docs/discovery/`
