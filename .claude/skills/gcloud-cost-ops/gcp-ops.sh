#!/usr/bin/env bash
# gcp-ops — GCP cost-ops over every account a session holds a cost-ops SA for (TBX-307).
#
# Each account alias has a JSON SA key in the env secret GCP_COST_OPS_KEY_<ALIAS>
# (never committed) and a line in GCP_COST_ACCOUNTS ("alias:org-id:ba1,ba2,…";
# several accounts separated by ';' or whitespace). The SessionStart hook
# activates every key as the named gcloud configuration `ops-<alias>`; this
# wrapper runs every call under that configuration (CLOUDSDK_ACTIVE_CONFIG_NAME),
# so the session's DEFAULT configuration — the read-only log reader — is never
# touched. Per-account facts that are not secrets (projects outside the org,
# projects / billing accounts known to be unreachable) live in
# accounts/<alias>.conf next to this script.
#
# Everything here is READ-ONLY except `log` (appends to docs/ops-log.md)
# and `run` (passes an arbitrary gcloud command through). A change to live
# infrastructure follows the proposal → "go" → execute → log contract in
# SKILL.md — this wrapper never decides to mutate on its own.
#
# Usage:
#   gcp-ops accounts                         # aliases, orgs, billing accounts, config state
#   gcp-ops auth <alias>                     # (re)activate ops-<alias> from its key (self-healing)
#   gcp-ops projects <alias>                 # every project: id, number, state, parent, billing account
#   gcp-ops inventory <alias> [--project P] [--types T1,T2] [--all] [--json]
#                                            # Cloud Asset Inventory: org scope + extra projects
#   gcp-ops costs <alias> <YYYY-MM> [--by service|project|sku] [--billing-account BA]
#                                            # from the BigQuery billing exports, per billing account,
#                                            # with the console invoice link to reconcile against
#   gcp-ops budgets <alias> [--billing-account BA]
#   gcp-ops run <alias> -- <gcloud args…>    # any gcloud command under ops-<alias>
#   gcp-ops bq  <alias> -- <bq args…>        # any bq command under ops-<alias>
#   gcp-ops log <alias> "<what ran>"         # append a dated line to docs/ops-log.md
#
# Examples:
#   gcp-ops inventory gce-strukturunion                       # counts per project × asset type
#   gcp-ops inventory gce-strukturunion --project ipx-server  # every resource of one project
#   gcp-ops costs gce-strukturunion 2026-11 --by project
#   gcp-ops run gce-strukturunion -- recommender recommendations list --project X \
#       --location europe-west1 --recommender google.compute.instance.IdleResourceRecommender
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
OPS_LOG="$REPO_ROOT/docs/ops-log.md"

die() { echo "gcp-ops: $*" >&2; exit 1; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# The web environment's CLOUDSDK_AUTH_ACCESS_TOKEN has a token type the APIs
# reject; empty == ignored, so gcloud/bq fall back to the configuration's SA.
export CLOUDSDK_AUTH_ACCESS_TOKEN=""
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ---------------------------------------------------------------- accounts --
# GCP_COST_ACCOUNTS entries: alias:org:ba1,ba2  (';' or whitespace separated)
account_entries() {
  [ -n "${GCP_COST_ACCOUNTS:-}" ] || die "GCP_COST_ACCOUNTS is not set (alias:org:ba1,ba2;…) — see docs/gcloud-cost-ops-access.md."
  printf '%s\n' "$GCP_COST_ACCOUNTS" | tr ';' '\n' | tr -s '[:space:]' '\n' | sed '/^$/d'
}
# Sets ALIAS, ORG, BILLING_ACCOUNTS (space separated), CONFIG, KEY_VAR for <alias>.
resolve_alias() {
  local want="$1" entry
  while IFS= read -r entry; do
    [ "${entry%%:*}" = "$want" ] || continue
    ALIAS="$want"
    local rest="${entry#*:}"
    ORG="${rest%%:*}"
    BILLING_ACCOUNTS="$(printf '%s' "${rest#*:}" | tr ',' ' ')"
    CONFIG="ops-${ALIAS}"
    KEY_VAR="GCP_COST_OPS_KEY_$(printf '%s' "$ALIAS" | tr '[:lower:]-' '[:upper:]_')"
    load_account_conf
    return 0
  done < <(account_entries)
  die "unknown account alias '$want' — known: $(account_entries | cut -d: -f1 | tr '\n' ' ')"
}
# accounts/<alias>.conf — plain key=value, parsed (not sourced):
#   extra_projects=p1 p2        projects outside the org the SA has rights on
#   unreachable_projects=p3     projects we know exist but hold no rights on
#   closed_billing_accounts=BA  billing accounts we hold no rights on
load_account_conf() {
  EXTRA_PROJECTS=""; UNREACHABLE_PROJECTS=""; CLOSED_BILLING_ACCOUNTS=""
  local f="$HERE/accounts/$ALIAS.conf" k v
  [ -f "$f" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in
      extra_projects)           EXTRA_PROJECTS="$v" ;;
      unreachable_projects)     UNREACHABLE_PROJECTS="$v" ;;
      closed_billing_accounts)  CLOSED_BILLING_ACCOUNTS="$v" ;;
      ''|'#'*) ;;
      *) echo "gcp-ops: ignoring unknown key '$k' in $f" >&2 ;;
    esac
  done < "$f"
}

# Every gcloud/bq call runs under the account's named configuration.
g()  { CLOUDSDK_ACTIVE_CONFIG_NAME="$CONFIG" gcloud "$@"; }
bqq() { CLOUDSDK_ACTIVE_CONFIG_NAME="$CONFIG" bq "$@"; }

# Account selected in the alias's configuration, or empty. `get-value` writes
# "(unset)" to stderr (dropped); normalise it anyway so a literal "(unset)" can
# never pass as an authenticated account or be handed to `auth revoke`.
config_account() {
  local v
  v="$(CLOUDSDK_ACTIVE_CONFIG_NAME="$CONFIG" gcloud config get-value account 2>/dev/null || true)"
  [ "$v" = "(unset)" ] && v=""
  printf '%s' "$v"
}

# Same rule as the session-start hook: a failed activation leaves NOTHING usable
# behind. The configuration goes (whether this call created it or a previous
# session did), and a pre-existing configuration's previously imported
# credential is revoked — unless another configuration (the default log reader)
# still uses that account. Otherwise `ensure_auth` would see a non-empty account
# and keep running on a credential whose key was already rotated away.
drop_failed_config() {
  local created="$1" stale_account deleted=1
  stale_account="$(config_account)"
  # gcloud refuses to delete the ACTIVE configuration (even via --configuration).
  # If someone activated ops-<alias> by hand, switch to `default` first
  # (recreating it if it is gone — `create` without --no-activate activates).
  if [ "$(gcloud config configurations list --filter=is_active:true --format='value(name)' 2>/dev/null)" = "$CONFIG" ]; then
    gcloud config configurations activate default --quiet >/dev/null 2>&1 \
      || gcloud config configurations create default --quiet >/dev/null 2>&1 || true
  fi
  gcloud config configurations delete "$CONFIG" --quiet >/dev/null 2>&1 || deleted=0
  [ -n "$stale_account" ] || return 0
  [ "$created" -eq 0 ] || return 0
  # Revoke when the configuration could not be removed (its account would stay
  # live) or when no other configuration (e.g. the log reader) uses the account.
  if [ "$deleted" -eq 0 ] \
     || ! gcloud config configurations list --format='value(properties.core.account)' 2>/dev/null \
          | grep -qxF "$stale_account"; then
    if gcloud auth revoke "$stale_account" --quiet >/dev/null 2>&1; then
      echo "gcp-ops: revoked the stale credential $stale_account left in $CONFIG." >&2
    else
      # Revocation was the last containment; say so instead of claiming success.
      die "ISOLATION FAILURE: could not revoke $stale_account (configuration $CONFIG $([ "$deleted" -eq 1 ] && echo deleted || echo 'still present')) — run \`gcloud auth revoke $stale_account\` and \`gcloud config configurations delete $CONFIG\` by hand before using gcloud."
    fi
  fi
  [ "$deleted" -eq 1 ] || echo "gcp-ops: WARNING could not delete configuration $CONFIG — its credential was revoked instead." >&2
}

# Self-healing auth: re-activate from the key if the configuration has no account.
# A configuration may only be used while its key secret still exists in the
# environment: with the secret gone, whatever credential an earlier session left
# in the configuration is purged and nothing runs (mirrors the hook's step 4).
ensure_auth() {
  [ -n "${!KEY_VAR:-}" ] && [ -n "$(config_account)" ] && return 0
  cmd_auth_impl   # no key -> purge + die; key but no account -> activate
}
# Every (re)activation — `auth` as well as the self-healing path — starts with
# the keyless check, so a configuration can never survive the loss of its key.
cmd_auth_impl() {
  local key="${!KEY_VAR:-}"
  if [ -z "$key" ]; then
    gcloud config configurations describe "$CONFIG" >/dev/null 2>&1 && drop_failed_config 0
    die "$KEY_VAR is not set — add the SA key as a Claude Code web env secret (see docs/gcloud-cost-ops-access.md)."
  fi
  local kf
  kf="$(mktemp)"; chmod 600 "$kf"
  trap 'rm -f "$kf"' EXIT INT TERM
  printf '%s' "$key" > "$kf"
  local created=0
  if ! gcloud config configurations describe "$CONFIG" >/dev/null 2>&1; then
    gcloud config configurations create "$CONFIG" --no-activate --quiet >/dev/null 2>&1
    created=1
  fi
  if ! g auth activate-service-account --key-file="$kf" --quiet >/dev/null 2>&1; then
    drop_failed_config "$created"
    die "failed to activate the cost-ops SA from $KEY_VAR (valid JSON key?)."
  fi
  local proj
  proj="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("project_id",""))' "$kf" 2>/dev/null || true)"
  rm -f "$kf"; trap - EXIT INT TERM
  [ -n "$proj" ] && g config set project "$proj" --quiet >/dev/null 2>&1 || true
  echo "activated $CONFIG as $(config_account) (project ${proj:-unset})"
}

# ---------------------------------------------------------------- commands --
cmd_accounts() {
  local entry alias rest org bas cfg acct
  printf '%-24s %-16s %-24s %-52s %s\n' ALIAS ORG CONFIG ACCOUNT BILLING_ACCOUNTS
  while IFS= read -r entry; do
    alias="${entry%%:*}"; rest="${entry#*:}"; org="${rest%%:*}"; bas="${rest#*:}"
    cfg="ops-$alias"
    acct="$(CLOUDSDK_ACTIVE_CONFIG_NAME="$cfg" gcloud config get-value account 2>/dev/null || true)"
    [ "$acct" = "(unset)" ] && acct=""
    printf '%-24s %-16s %-24s %-52s %s\n' "$alias" "${org:--}" "$cfg" "${acct:-<not activated>}" "$bas"
  done < <(account_entries)
}

cmd_auth() { resolve_alias "$1"; cmd_auth_impl; }

cmd_projects() {
  resolve_alias "$1"; ensure_auth
  local p err
  # The org listing is the backbone of the report: a failure (auth, quota, API)
  # is an error, not an empty list that reads as "no projects".
  PROJECTS_LIST_FILE="$(mktemp)"
  trap 'rm -f "${PROJECTS_LIST_FILE:-}"' EXIT INT TERM
  if ! err="$(g projects list --format=json 2>&1 > "$PROJECTS_LIST_FILE")"; then
    die "project listing failed — report would be incomplete, not printed: $(printf '%s\n' "$err" | tail -1)"
  fi
  {
    cat "$PROJECTS_LIST_FILE"
    for p in $EXTRA_PROJECTS; do
      g projects describe "$p" --format=json 2>/dev/null \
        || echo "gcp-ops: WARNING extra project $p could not be described (no rights? deleted?) — missing from the list" >&2
    done
  } | python3 "$HERE/gcp_ops_lib.py" projects "$CONFIG" "$UNREACHABLE_PROJECTS" "$CLOSED_BILLING_ACCOUNTS"
  rm -f "$PROJECTS_LIST_FILE"; trap - EXIT INT TERM
}

cmd_inventory() {
  resolve_alias "$1"; shift; ensure_auth
  local project="" types="" all=0 as_json=0 err
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="${2:?--project needs a value}"; shift 2 ;;
      --types)   types="${2:?--types needs a value}"; shift 2 ;;
      --all)     all=1; shift ;;
      --json)    as_json=1; shift ;;
      *) die "unknown option '$1' (see --help)." ;;
    esac
  done
  local -a scopes=()
  if [ -n "$project" ]; then
    scopes=("projects/$project")
  else
    [ -n "$ORG" ] && scopes+=("organizations/$ORG")
    local p; for p in $EXTRA_PROJECTS; do scopes+=("projects/$p"); done
  fi
  [ "${#scopes[@]}" -gt 0 ] || die "nothing to scan: no org in GCP_COST_ACCOUNTS and no extra_projects in accounts/$ALIAS.conf."
  local -a args=(--format=json --page-size=500)
  [ -n "$types" ] && args+=(--asset-types="$types")
  # The search API names projects by number; map them back to ids for the reader.
  # `projects list` does not return out-of-org extra projects, so describe each.
  INV_PROJECTS_FILE="$(mktemp)"
  trap 'rm -f "${INV_PROJECTS_FILE:-}"' EXIT INT TERM
  # A failed listing would silently degrade every PROJECT column to a number;
  # like `projects`, treat it as an error.
  if ! err="$(g projects list --format=json 2>&1 > "$INV_PROJECTS_FILE")"; then
    die "project listing failed — inventory could not map project numbers to ids: $(printf '%s\n' "$err" | tail -1)"
  fi
  local p
  for p in $EXTRA_PROJECTS; do
    g projects describe "$p" --format=json >> "$INV_PROJECTS_FILE" 2>/dev/null \
      || echo "gcp-ops: WARNING extra project $p could not be described — its assets will show under the project number" >&2
  done
  # Every scope must answer: a failed search (auth, quota, lost org permission)
  # would otherwise be reported as "no resources" and hide whole projects.
  INV_SCOPES_FILE="$(mktemp)"
  trap 'rm -f "${INV_PROJECTS_FILE:-}" "${INV_SCOPES_FILE:-}"' EXIT INT TERM
  local s err
  for s in "${scopes[@]}"; do
    if ! err="$(g asset search-all-resources --scope="$s" "${args[@]}" 2>&1 >> "$INV_SCOPES_FILE")"; then
      die "asset search failed for scope $s — inventory would be incomplete, not reported: $(printf '%s\n' "$err" | tail -1)"
    fi
  done
  python3 "$HERE/gcp_ops_lib.py" inventory "$all" "$as_json" "$project" "$INV_PROJECTS_FILE" < "$INV_SCOPES_FILE"
  rm -f "$INV_PROJECTS_FILE" "$INV_SCOPES_FILE"; trap - EXIT INT TERM
}

# Billing-export tables are discovered through Cloud Asset Inventory, so nothing
# about where an export lands is hard-coded: one BigQuery table per billing
# account, named gcp_billing_export_v1_<BA with _>.
export_tables() {
  local s err names=""
  for s in "${EXPORT_SCOPES[@]}"; do
    # A failed lookup (auth, quota, API) must not read as "no export": die here.
    if ! err="$(g asset search-all-resources --scope="$s" \
          --asset-types=bigquery.googleapis.com/Table --format='value(name)' 2>&1 >> "$EXPORT_NAMES_FILE")"; then
      die "export discovery failed for scope $s: $(printf '%s\n' "$err" | tail -1)"
    fi
  done
  # `grep` exits 1 on no match; that IS the expected answer for a billing
  # account whose export has not landed yet, so it is tolerated here — the
  # caller prints the "no export table" diagnostic.
  { grep -F '/tables/gcp_billing_export_v1_' "$EXPORT_NAMES_FILE" || true; } \
    | sed -E 's#^//bigquery.googleapis.com/projects/([^/]+)/datasets/([^/]+)/tables/(.+)$#\1.\2.\3#' | sort -u
}

cmd_costs() {
  resolve_alias "$1"; shift; ensure_auth
  local month="${1:?costs needs <YYYY-MM>}"; shift
  [[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "month must be YYYY-MM (got '$month')."
  local by="service" only_ba=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --by) by="${2:?--by needs service|project|sku}"; shift 2 ;;
      --billing-account) only_ba="${2:?--billing-account needs a value}"; shift 2 ;;
      *) die "unknown option '$1' (see --help)." ;;
    esac
  done
  local dim
  case "$by" in
    service) dim="service.description" ;;
    project) dim="IFNULL(project.id, '(no project)')" ;;
    sku)     dim="CONCAT(service.description, ' / ', sku.description)" ;;
    *) die "--by must be service, project or sku." ;;
  esac
  EXPORT_SCOPES=()
  [ -n "$ORG" ] && EXPORT_SCOPES+=("organizations/$ORG")
  local p; for p in $EXTRA_PROJECTS; do EXPORT_SCOPES+=("projects/$p"); done
  local invoice_month="${month/-/}" tables t ba
  EXPORT_NAMES_FILE="$(mktemp)"
  trap 'rm -f "${EXPORT_NAMES_FILE:-}"' EXIT INT TERM
  tables="$(export_tables)"
  rm -f "$EXPORT_NAMES_FILE"; trap - EXIT INT TERM
  [ -n "$tables" ] || die "no gcp_billing_export_v1_* table found via Asset Inventory in ${EXPORT_SCOPES[*]} — export not enabled, or not landed yet."
  for ba in $BILLING_ACCOUNTS; do
    echo "=================================================================="
    echo "Billing account $ba — invoice month $month"
    echo "Invoice / statement to reconcile against: https://console.cloud.google.com/billing/$ba/documents"
    if printf '%s\n' $CLOSED_BILLING_ACCOUNTS | grep -qx "$ba"; then
      echo "  (closed / no rights — listed from accounts/$ALIAS.conf; nothing to query)"
      continue
    fi
    [ -z "$only_ba" ] || [ "$only_ba" = "$ba" ] || { echo "  (skipped — --billing-account $only_ba)"; continue; }
    t="$(printf '%s\n' "$tables" | grep -F "gcp_billing_export_v1_${ba//-/_}" | head -1 || true)"
    if [ -z "$t" ]; then
      echo "  no export table for this billing account (not enabled, or first rows not landed yet)"
      continue
    fi
    local proj="${t%%.*}"
    echo "  source: $t"
    local out
    out="$(bqq --project_id="$proj" query --nouse_legacy_sql --format=pretty --max_rows=200 "
      SELECT ${dim} AS ${by},
             currency,
             ROUND(SUM(cost), 2) AS cost,
             ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS credits,
             ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS net
      FROM \`${t}\`
      WHERE invoice.month = '${invoice_month}'
      GROUP BY 1, 2
      ORDER BY net DESC" 2>&1)" || { echo "  query failed: $(printf '%s\n' "$out" | tail -1)"; continue; }
    if [ -z "$out" ]; then
      echo "  (no rows for invoice month $invoice_month in the export — see the history range below)"
    else
      printf '%s\n' "$out"
    fi
    # cost_type splits the export rows the way the invoice does: regular usage,
    # tax, adjustments, rounding. The total is therefore tax-INCLUSIVE — it is the
    # invoice's bottom line, not a pre-tax subtotal (Cloud Billing docs,
    # "Return the total costs on an invoice").
    bqq --project_id="$proj" query --nouse_legacy_sql --format=pretty "
      SELECT currency,
             ROUND(SUM(IF(cost_type = 'regular', cost, 0)), 2) AS regular,
             ROUND(SUM(IF(cost_type = 'tax', cost, 0)), 2) AS tax,
             ROUND(SUM(IF(cost_type = 'adjustment', cost, 0)), 2) AS adjustments,
             ROUND(SUM(IF(cost_type = 'rounding_error', cost, 0)), 2) AS rounding,
             ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS credits,
             ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS invoice_total,
             MIN(usage_start_time) AS first_usage_in_export,
             MAX(usage_start_time) AS last_usage_in_export
      FROM \`${t}\`
      WHERE invoice.month = '${invoice_month}'
      GROUP BY 1" || true
    echo "  'invoice_total' = regular + tax + adjustments + rounding + credits — the console invoice's bottom line for $month, tax INCLUDED; the pre-tax subtotal is invoice_total - tax (= regular + adjustments + rounding + credits)."
    echo "  Export history in this table starts at:"
    bqq --project_id="$proj" query --nouse_legacy_sql --format=csv \
      "SELECT MIN(usage_start_time) AS export_starts, MAX(export_time) AS last_export FROM \`${t}\`" 2>/dev/null | tail -n +2 | sed 's/^/    /' || true
  done
}

cmd_budgets() {
  resolve_alias "$1"; shift; ensure_auth
  local only_ba="" ba
  while [ $# -gt 0 ]; do
    case "$1" in
      --billing-account) only_ba="${2:?}"; shift 2 ;;
      *) die "unknown option '$1' (see --help)." ;;
    esac
  done
  for ba in $BILLING_ACCOUNTS; do
    [ -z "$only_ba" ] || [ "$only_ba" = "$ba" ] || continue
    echo "== Billing account $ba  (budgets: https://console.cloud.google.com/billing/$ba/budgets)"
    if printf '%s\n' $CLOSED_BILLING_ACCOUNTS | grep -qx "$ba"; then
      echo "   (closed / no rights)"; continue
    fi
    local err
    if ! err="$(g billing budgets list --billing-account="$ba" \
        --format='table(displayName,amount.specifiedAmount.units,amount.specifiedAmount.currencyCode,amount.lastPeriodAmount.yesno(yes="last period"),budgetFilter.projects.list(),thresholdRules.list():label=THRESHOLDS)' 2>&1)"; then
      echo "   listing failed: $(printf '%s\n' "$err" | grep -m1 -E 'ERROR|error' | cut -c1-220)"
      echo "   (needs billing.budgets.list on the account AND billingbudgets.googleapis.com enabled on the SA's quota project)"
    else
      printf '%s\n' "${err:-   (no budgets)}"
    fi
  done
}

cmd_run() {
  resolve_alias "$1"; shift; ensure_auth
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || die "run needs a gcloud command after '--'."
  exec env CLOUDSDK_ACTIVE_CONFIG_NAME="$CONFIG" gcloud "$@"
}
cmd_bq() {
  resolve_alias "$1"; shift; ensure_auth
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || die "bq needs a bq command after '--'."
  exec env CLOUDSDK_ACTIVE_CONFIG_NAME="$CONFIG" bq "$@"
}

cmd_log() {
  resolve_alias "$1"; shift
  local text="${1:?log needs the text of the line}"
  [ -f "$OPS_LOG" ] || die "$OPS_LOG does not exist."
  local line
  line="- $(date '+%Y-%m-%d %H:%M %Z') (Claude, $ALIAS): $text"
  printf '%s\n' "$line" >> "$OPS_LOG"
  echo "appended to docs/ops-log.md:"
  echo "$line"
}

main() {
  [ $# -ge 1 ] || { usage; exit 2; }
  local cmd="$1"; shift
  case "$cmd" in
    -h|--help|help) usage ;;
    accounts)  cmd_accounts ;;
    auth)      cmd_auth "${1:?auth needs <alias>}" ;;
    projects)  cmd_projects "${1:?projects needs <alias>}" ;;
    inventory) cmd_inventory "${1:?inventory needs <alias>}" "${@:2}" ;;
    costs)     cmd_costs "${1:?costs needs <alias> <YYYY-MM>}" "${@:2}" ;;
    budgets)   cmd_budgets "${1:?budgets needs <alias>}" "${@:2}" ;;
    run)       cmd_run "${1:?run needs <alias> -- <gcloud args>}" "${@:2}" ;;
    bq)        cmd_bq "${1:?bq needs <alias> -- <bq args>}" "${@:2}" ;;
    log)       cmd_log "${1:?log needs <alias> \"<text>\"}" "${@:2}" ;;
    *) die "unknown command '$cmd' (see --help)." ;;
  esac
}

main "$@"
