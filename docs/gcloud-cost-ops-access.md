# GCP cost-ops access from Claude Code sessions (TBX-307)

A Claude Code session that looks after our Google Cloud spend needs to see
**every project, resource and invoice** of an account, and — after an explicit
"go" — to **change** things: cleanup policies, secret versions, idle resources.
This runbook describes the **cost-ops service account** that gives a session those
rights, how a session activates it, and the contract that keeps those rights safe.
The session-side skill is
[`.claude/skills/gcloud-cost-ops/`](../.claude/skills/gcloud-cost-ops/SKILL.md).

> **This SA is not read-only.** Org-level `roles/editor` plus `billing.admin` can
> reshape the whole account. Three things contain that: (1) the SessionStart hook
> activates it as a **named** gcloud configuration `ops-<alias>`, never the
> default, so nothing runs with it by accident; (2) the skill's **safeguard
> contract** — every change is a written proposal that runs only after an explicit
> "go", destructive acts are confirmed one by one, every executed change gets a
> dated line in [`docs/ops-log.md`](ops-log.md); (3) the key is a
> web-environment secret, rotated as described in §4.

---

## 1. Accounts (as provisioned)

| Alias | Org | Workspace | SA | Billing accounts |
|---|---|---|---|---|
| `gce-strukturunion` | `134549734014` | strukturunion.de | `claude-cost-ops@claude-ops-gce-strukturunion.iam.gserviceaccount.com` | `006404-E97FEA-AEE3E8`, `01B7AE-4C9C58-226EFD`, `01D678-3F25F0-2D70DA` (+ closed `0032D4-604121-C75402`, no rights) |
| `gce-mdbx` | `526430919328` | md-bx.de | `claude-cost-ops@claude-ops-gce-mdbx.iam.gserviceaccount.com` | `010E7E-C918EB-0E7DBD` |

Roles held by each SA (org level; for `gce-strukturunion` also on
`api-project-531243544567` outside the org): `roles/editor`,
`roles/cloudasset.viewer`, `roles/recommender.viewer`,
`roles/iam.securityReviewer`, `roles/serviceusage.serviceUsageAdmin`,
`roles/secretmanager.secretVersionManager`, `roles/artifactregistry.admin`;
`roles/billing.admin` on the account's open billing accounts. Not reachable, by
decision (`gce-strukturunion`): the closed billing account and its projects
`imperial-terra-205507`, `fluent-buckeye-205507`.

*As provisioned 2026-11-04 by `claude-ops-setup.sh` (operator side); verified
live from a session 2026-11-04 for both accounts — `gcloud billing accounts list`
returns the open accounts, `gcloud asset search-all-resources
--scope=organizations/<org>` returns resources, `gcloud organizations list`
returns nothing (expected: `roles/editor` lacks
`resourcemanager.organizations.get`; org-scoped asset search does not need it).*

BigQuery billing exports (standard, detailed, pricing), enabled 2026-11-04:

| Billing account | Export dataset |
|---|---|
| `006404-E97FEA-AEE3E8` | `claude-ops-gce-strukturunion.billing_export` |
| `01B7AE-4C9C58-226EFD` | `cloudrun-strukturunion-toolbox.billing_export` |
| `01D678-3F25F0-2D70DA` | `prakti-app.billing_export` (EU) |
| `010E7E-C918EB-0E7DBD` | `claude-ops-gce-mdbx.billing_export` (EU) |

No continuous history before 2026-11-04 (the `006404` table holds a two-day
sliver, 2026-09-30 → 2026-10-02, from an earlier attempt). The skill discovers
the tables through Asset Inventory, so this table is documentation, not config.

A further account follows with the same operator script; it needs only its key
secret, its `GCP_COST_ACCOUNTS` entry, and — if it has projects outside its org
or known-unreachable projects / billing accounts — an `accounts/<alias>.conf` in
the skill directory (`gce-mdbx` has none: all five projects are in the org).

---

## 2. Web-environment secrets

| Variable | Value |
|---|---|
| `GCP_COST_OPS_KEY_<ALIAS>` | the SA's JSON key, single line. `<ALIAS>` is the account alias upper-cased with `-`→`_`: `GCP_COST_OPS_KEY_GCE_STRUKTURUNION`, `GCP_COST_OPS_KEY_GCE_MDBX`. |
| `GCP_COST_ACCOUNTS` | `alias:org-id:ba1,ba2,…`; several accounts separated by `;` or whitespace. Live value: `gce-strukturunion:134549734014:0032D4-604121-C75402,006404-E97FEA-AEE3E8,01B7AE-4C9C58-226EFD,01D678-3F25F0-2D70DA;gce-mdbx:526430919328:010E7E-C918EB-0E7DBD` |

The key is **never committed**. Environment changes apply at the **next** session
start. The hook matches the variable name exactly (`^GCP_COST_OPS_KEY_[A-Za-z0-9_]+$`)
— a mistyped prefix is silently not a cost-ops key; the hook then prints
`NOTE: no GCP cost-ops config active …` at session start.

---

## 3. How a session authenticates (no manual steps)

[`.claude/hooks/session-start.sh`](../.claude/hooks/session-start.sh) runs on
every web session. It first makes `default` the **active** configuration again
(a previous or resumed session may have activated an `ops-*` one by hand —
`gcloud config …` is allow-listed; a deleted `default` is recreated, which
activates it) and clears any account selected in it, so "bare `gcloud` =
unprivileged, account-less `default`" holds at every session start. This
repository has no log reader; `default` never carries a credential. If `default`
cannot be made active or its account cannot be unset, the hook prints a `NOTE:`
and stops before touching any cost-ops configuration. Then it:

1. Finds every `GCP_COST_OPS_KEY_<ALIAS>` in the environment.
2. Creates the gcloud configuration `ops-<alias>` if missing (**not** activated),
   materialises the key to a private temp file, activates the SA **inside that
   configuration** (`CLOUDSDK_ACTIVE_CONFIG_NAME=ops-<alias>`), sets the
   configuration's project to the key's `project_id` (the SA's home project,
   which is also the quota project for org-scoped Asset / Recommender calls),
   and deletes the temp file.
3. Purges every `ops-*` configuration no `GCP_COST_OPS_KEY_*` variable names any
   more (secret removed from the environment): configuration deleted, its
   credential revoked. The wrapper applies the same rule at call time — a
   configuration is usable only while its key secret exists.
4. Prints one stdout `NOTE:` line naming the active configs — or the failed ones
   (empty / invalid key), without breaking the session (exit 0). A failed
   activation — or an emptied key — leaves nothing usable behind: the
   configuration is removed, and if it pre-existed (a key rotated to an invalid
   or empty one), the stale credential it pointed at is revoked — so a reported
   failure can never hide a still-working privileged credential.

Verify from a session:

```bash
gcloud config configurations list          # default = active, no account; ops-<alias> = cost-ops
.claude/skills/gcloud-cost-ops/gcp-ops.sh accounts
.claude/skills/gcloud-cost-ops/gcp-ops.sh run gce-strukturunion -- billing accounts list
```

The web environment injects a `CLOUDSDK_AUTH_ACCESS_TOKEN` whose token type the
Google APIs reject (`ACCESS_TOKEN_TYPE_UNSUPPORTED`); gcloud would prefer it over
the activated SA. The hook and the wrapper both neutralise it by exporting it
empty (an empty value is ignored; `unset` would not survive the session env
file).

---

## 4. Rotation / revocation

```bash
SA=claude-cost-ops@claude-ops-gce-strukturunion.iam.gserviceaccount.com   # or …@claude-ops-gce-mdbx.…
gcloud iam service-accounts keys list --iam-account="$SA"
gcloud iam service-accounts keys create /tmp/cost-ops.json --iam-account="$SA"   # new key → env secret
gcloud iam service-accounts keys delete <OLD_KEY_ID> --iam-account="$SA"         # after the next session confirmed the new one
rm -f /tmp/cost-ops.json
```

To cut an SA off entirely: `gcloud iam service-accounts disable "$SA"` — its
`ops-<alias>` configuration stops working at the next API call. **NOT YET
APPLIED** — no rotation has been necessary so far.

---

## 5. Related

- Skill: [`.claude/skills/gcloud-cost-ops/SKILL.md`](../.claude/skills/gcloud-cost-ops/SKILL.md)
- Change log (every executed change): [`docs/ops-log.md`](ops-log.md)
- Discovery reports: [`docs/discovery/`](discovery/)
- Hook: [`.claude/hooks/session-start.sh`](../.claude/hooks/session-start.sh) · registered in [`.claude/settings.json`](../.claude/settings.json)
