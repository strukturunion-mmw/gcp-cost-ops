# gcp-cost-ops

Cost-ops for the strukturunion Google Cloud accounts (`gce-strukturunion`, org 134549734014, and
`gce-mdbx`, org 526430919328): what runs where, what it costs, which budgets guard it, and the
clean-up of idle resources. Claude Code sessions do the discovery freely; every change to live
infrastructure is a written proposal that runs only after an explicit "go", destructive acts are
confirmed one by one, and every executed change gets a dated line in the ops log. The contract and
the pointers for a session are in `CLAUDE.md`.

A session authenticates without manual steps: the SessionStart hook `.claude/hooks/session-start.sh`
installs the Google Cloud CLI if needed and activates every cost-ops service account whose JSON key
is present as a web-environment secret `GCP_COST_OPS_KEY_<ALIAS>` as its own named gcloud
configuration `ops-<alias>`. The `default` configuration is kept active and account-less, so a bare
`gcloud` call is unprivileged; the skill wrapper `gcp-ops.sh` opts in per call with
`CLOUDSDK_ACTIVE_CONFIG_NAME=ops-<alias>`. Keys are never committed; the account list comes from
`GCP_COST_ACCOUNTS`. Setup, roles and rotation: `docs/gcloud-cost-ops-access.md`.

Where things are: the skill and wrapper in `.claude/skills/gcloud-cost-ops/` (`SKILL.md` explains
every report and the proposal → go → execute → log cycle), the Notion board skill in
`.claude/skills/notion-board/`, the runbook in `docs/gcloud-cost-ops-access.md`, the append-only
change log in `docs/ops-log.md`, and the per-account discovery reports in `docs/discovery/`.
