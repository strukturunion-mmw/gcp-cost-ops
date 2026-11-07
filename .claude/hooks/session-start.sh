#!/bin/bash
# SessionStart hook — Google Cloud CLI + cost-ops service-account activation for
# Claude Code sessions of the gcp-cost-ops repository.
#
# Installs the Google Cloud CLI (once, idempotent) and activates every GCP
# COST-OPS SA (`claude-cost-ops@…`) a fresh ephemeral web session holds a key
# for, with no manual steps — each as its OWN NAMED configuration `ops-<alias>`
# (TBX-307), one per env secret GCP_COST_OPS_KEY_<ALIAS> (alias = the suffix,
# lower-cased, `_` → `-`; e.g. GCP_COST_OPS_KEY_GCE_STRUKTURUNION → config
# `ops-gce-strukturunion`). These SAs hold org-level editor + billing.admin, so
# they are deliberately kept OUT of the default configuration: nothing runs with
# them unless a command opts in with CLOUDSDK_ACTIVE_CONFIG_NAME=ops-<alias>
# (the gcloud-cost-ops skill wrapper does exactly that). Runbook:
# docs/gcloud-cost-ops-access.md.
#
# This repository has NO log reader: the `default` configuration is kept ACTIVE
# and EMPTY (no account, no project) at every session start, so a bare
# `gcloud …` call is always unprivileged.
#
# Keys are JSON SA keys supplied as Claude Code web environment secrets — never
# committed. Each is materialised to a private temp file only for the activation
# call and deleted immediately afterwards (gcloud keeps the activated credential
# under ~/.config/gcloud).
#
# Design notes:
#   - Runs only in Claude Code on the web (CLAUDE_CODE_REMOTE=true); a no-op locally.
#   - Idempotent: skips the install when gcloud is already present; re-activating
#     an already-activated SA / re-using an existing named configuration is fine.
#   - Degrades gracefully: a missing or invalid key never breaks the session — it
#     prints ONE stdout NOTE line (so the model knows; stderr does not reach it)
#     and carries on with exit 0.
set -euo pipefail

# Diagnostics go to stderr so they don't get injected into the session context.
log() { echo "[gcloud-hook] $*" >&2; }

# Only run in the remote (web) ephemeral environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SDK_DIR="$HOME/google-cloud-sdk"
SDK_TARBALL_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz"
RUNBOOK="docs/gcloud-cost-ops-access.md"

# 1) Install the Cloud SDK once (idempotent; cached into the container image).
if command -v gcloud >/dev/null 2>&1; then
  log "Cloud CLI already on PATH; skipping install."
elif [ -x "$SDK_DIR/bin/gcloud" ]; then
  log "Cloud CLI already installed at $SDK_DIR; skipping install."
else
  log "Installing Google Cloud CLI…"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/gcloud.tar.gz" "$SDK_TARBALL_URL"
  tar -xzf "$tmp/gcloud.tar.gz" -C "$HOME"
  rm -rf "$tmp"
  "$SDK_DIR/install.sh" --quiet --usage-reporting=false \
    --path-update=false --command-completion=false >/dev/null
  log "Cloud CLI installed at $SDK_DIR."
fi

# Put gcloud on PATH for this turn and persist it for the rest of the session.
if [ -x "$SDK_DIR/bin/gcloud" ]; then
  export PATH="$SDK_DIR/bin:$PATH"
  if [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -q 'google-cloud-sdk/bin' "$CLAUDE_ENV_FILE" 2>/dev/null; then
    echo "export PATH=\"$SDK_DIR/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

# The web environment injects a CLOUDSDK_AUTH_ACCESS_TOKEN whose token type the
# Google APIs reject (ACCESS_TOKEN_TYPE_UNSUPPORTED). gcloud prefers that env
# token over any activated SA, so a bare `gcloud …` call would fail with an
# *auth* error even though the SA is fine. Neutralise it: an EMPTY value is
# ignored by gcloud, so it falls back to the configuration's SA. Persist the
# override for the rest of the session (an empty `export` survives the env-file
# mechanism; `unset` would not), and apply it to this turn too.
neutralise_env_token() {
  export CLOUDSDK_AUTH_ACCESS_TOKEN=""
  if [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -q 'CLOUDSDK_AUTH_ACCESS_TOKEN=' "$CLAUDE_ENV_FILE" 2>/dev/null; then
    echo 'export CLOUDSDK_AUTH_ACCESS_TOKEN=""' >> "$CLAUDE_ENV_FILE"
  fi
}

active_config() { gcloud config configurations list --filter=is_active:true --format='value(name)' 2>/dev/null || true; }
# Account selected in configuration $1, or empty. `get-value` writes "(unset)"
# to stderr (dropped here); normalise it anyway in case a gcloud version ever
# prints the sentinel on stdout — a literal "(unset)" must never be revoked or
# treated as an authenticated account.
config_account_of() {
  local v
  v="$(CLOUDSDK_ACTIVE_CONFIG_NAME="$1" gcloud config get-value account 2>/dev/null || true)"
  [ "$v" = "(unset)" ] && v=""
  printf '%s' "$v"
}

# Belt and braces: whatever temp key file is in flight when the hook aborts
# (`set -e`, signal) must not linger. activate_sa_key removes its own file on the
# normal path; this catches the abnormal one.
_hook_tmp_keys=()
cleanup_tmp_keys() { rm -f "${_hook_tmp_keys[@]:-}"; }
trap cleanup_tmp_keys EXIT INT TERM

# activate_sa_key <key-json> <config-name>
#   Materialises the JSON key to a private temp file, activates the SA inside
#   the named gcloud configuration (creating it, non-active, if missing), and
#   deletes the file again on every exit path. Every activation is scoped to an
#   explicit configuration — never to "whatever is active" — so a configuration
#   a previous session left active can neither receive the wrong credential nor
#   keep a privileged one. Returns non-zero when activation fails.
activate_sa_key() {
  local key_json="$1" config="$2" key_file rc=0
  key_file="$(mktemp)"
  _hook_tmp_keys+=("$key_file")
  chmod 600 "$key_file"
  printf '%s' "$key_json" > "$key_file"
  if ! gcloud config configurations describe "$config" >/dev/null 2>&1; then
    gcloud config configurations create "$config" --no-activate --quiet >/dev/null 2>&1 || rc=1
  fi
  # CLOUDSDK_ACTIVE_CONFIG_NAME scopes the activation to that configuration
  # without touching which configuration is *active* for the session.
  [ "$rc" -eq 0 ] && { CLOUDSDK_ACTIVE_CONFIG_NAME="$config" \
    gcloud auth activate-service-account --key-file="$key_file" --quiet >/dev/null 2>&1 || rc=$?; }
  # A failed activation must leave NO usable credential behind (see purge_config).
  [ "$rc" -eq 0 ] || purge_config "$config" || true
  rm -f "$key_file"
  return "$rc"
}

# purge_config <config-name>
#   Removes a configuration that may no longer be trusted and revokes the
#   credential it pointed at — unless another configuration still uses that
#   account. Used whenever a cost-ops key is absent, empty or fails to activate:
#   a configuration from an earlier session would otherwise keep a previously
#   authorised org-editor/billing-admin credential stored and usable while the
#   hook reports a failure. No-op when the configuration does not exist.
purge_config() {
  local config="$1" stale_account deleted=1
  gcloud config configurations describe "$config" >/dev/null 2>&1 || return 0
  stale_account="$(config_account_of "$config")"
  # gcloud refuses to delete the ACTIVE configuration; step 2 pinned `default`
  # as active, but stay safe if that ever changes.
  if [ "$(active_config)" = "$config" ]; then
    gcloud config configurations activate default --quiet >/dev/null 2>&1 \
      || gcloud config configurations create default --quiet >/dev/null 2>&1 || true
  fi
  gcloud config configurations delete "$config" --quiet >/dev/null 2>&1 || deleted=0
  [ -n "$stale_account" ] || return 0
  # Revoke when the configuration could not be removed (its account would stay
  # live) or when no other configuration uses the account.
  if [ "$deleted" -eq 0 ] \
     || ! gcloud config configurations list --format='value(properties.core.account)' 2>/dev/null \
          | grep -qxF "$stale_account"; then
    if gcloud auth revoke "$stale_account" --quiet >/dev/null 2>&1; then
      log "Revoked the stale credential $stale_account left in $config."
    else
      # Revocation was the last containment. Report the failure where the
      # model sees it (stdout) rather than claim success; the session keeps
      # running (exit 0 at the end), but nothing here hides the problem.
      log "ERROR: could not revoke $stale_account (configuration $config $([ "$deleted" -eq 1 ] && echo deleted || echo 'still present'))."
      echo "NOTE: GCP ISOLATION FAILURE — credential $stale_account of configuration $config could not be revoked; run \`gcloud auth revoke $stale_account\` and \`gcloud config configurations delete $config\` by hand before using gcloud."
      return 1
    fi
  fi
  [ "$deleted" -eq 1 ] || log "WARNING: could not delete configuration $config — its credential was revoked instead."
}

# 2) `default` must be the ACTIVE configuration and carry NO account. The
#    isolation story is "bare gcloud = unprivileged": a previous or resumed
#    session may have activated an `ops-*` configuration by hand (`gcloud
#    config …` is allow-listed), or run `gcloud config set account` with a
#    cost-ops SA while `default` was active — either would otherwise persist.
if [ "$(active_config)" != "default" ]; then
  if gcloud config configurations activate default --quiet >/dev/null 2>&1; then
    log "Switched the active gcloud configuration back to default."
  # A deleted `default` cannot be activated; `create` without --no-activate
  # creates AND activates it, so bare gcloud is unprivileged again.
  elif gcloud config configurations create default --quiet >/dev/null 2>&1; then
    log "Recreated and activated the default gcloud configuration."
  fi
fi
if [ "$(active_config)" != "default" ]; then
  # Without an unprivileged active configuration nothing below is safe: a
  # cost-ops configuration left active by an earlier session would stay behind
  # bare gcloud. Say so on stdout and stop before step 3 — never activate more.
  echo "NOTE: gcloud default configuration could not be made active (active: '$(active_config)') — cost-ops activation SKIPPED; run \`gcloud config configurations activate default\` and restart the session (see $RUNBOOK)."
  exit 0
fi
# `default` must carry NO account at all. Fails closed: if the account cannot
# be unset (read-only config dir, …) the hook says so on stdout and stops
# before activating anything else.
clear_default_account() {
  local acct
  acct="$(config_account_of default)"
  [ -n "$acct" ] || return 0
  if CLOUDSDK_ACTIVE_CONFIG_NAME=default gcloud config unset account --quiet >/dev/null 2>&1 \
     && [ -z "$(config_account_of default)" ]; then
    log "Cleared account $acct from the default configuration (default must stay account-less)."
    return 0
  fi
  log "ERROR: could not clear account $acct from the default configuration."
  echo "NOTE: GCP ISOLATION FAILURE — account $acct is still selected in the default gcloud configuration and could not be unset; run \`gcloud config unset account\` (and \`gcloud auth revoke $acct\`) by hand before using gcloud. Cost-ops activation SKIPPED."
  exit 0
}
clear_default_account

# 3) Activate every cost-ops SA as its own named configuration `ops-<alias>`.
#    The default configuration stays exactly as step 2 left it: active, empty.
cost_ops_configs=()
cost_ops_failed=()
cost_ops_seen=()   # every ops-* configuration this run decided about
while IFS= read -r var; do
  [ -n "$var" ] || continue
  alias_raw="${var#GCP_COST_OPS_KEY_}"
  alias_name="$(printf '%s' "$alias_raw" | tr '[:upper:]_' '[:lower:]-')"
  config="ops-${alias_name}"
  cost_ops_seen+=("$config")
  key_json="${!var}"
  if [ -z "$key_json" ]; then
    log "$var is set but empty — skipping config $config."
    purge_config "$config" || true   # an earlier session's credential must not survive an emptied key
    cost_ops_failed+=("$config")
    continue
  fi
  if activate_sa_key "$key_json" "$config"; then
    # The SA's home project (from the key) becomes the configuration's default
    # project — it is also the quota project for org-scoped Asset / Recommender
    # calls. Best effort: a key without project_id simply leaves it unset.
    sa_project="$(printf '%s' "$key_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("project_id",""))' 2>/dev/null || true)"
    if [ -n "$sa_project" ]; then
      CLOUDSDK_ACTIVE_CONFIG_NAME="$config" gcloud config set project "$sa_project" --quiet >/dev/null 2>&1 || true
    fi
    neutralise_env_token
    cost_ops_configs+=("$config")
    log "Activated cost-ops SA from $var as gcloud configuration $config (project ${sa_project:-unset})."
  else
    cost_ops_failed+=("$config")
    log "WARNING: failed to activate the cost-ops SA from $var (invalid JSON key?)."
  fi
done < <(compgen -v | grep -E '^GCP_COST_OPS_KEY_[A-Za-z0-9_]+$' || true)

# 4) An ops-* configuration whose key variable is GONE (secret removed from the
#    environment, not just emptied) never enters the loop above, yet it would
#    keep an earlier session's privileged credential stored and usable. Every
#    ops-* configuration this run did not decide about is purged.
cost_ops_purged=()
while IFS= read -r existing; do
  [ -n "$existing" ] || continue
  seen=0
  for c in "${cost_ops_seen[@]:-}"; do [ "$c" = "$existing" ] && seen=1; done
  [ "$seen" -eq 1 ] && continue
  if purge_config "$existing"; then
    cost_ops_purged+=("$existing")
    log "Purged $existing: no GCP_COST_OPS_KEY_* variable names it any more."
  fi
done < <(gcloud config configurations list --format='value(name)' 2>/dev/null | grep -E '^ops-' || true)

if [ "${#cost_ops_purged[@]}" -gt 0 ]; then
  echo "NOTE: GCP cost-ops configs purged (their key secret is gone): ${cost_ops_purged[*]}."
fi
if [ "${#cost_ops_configs[@]}" -gt 0 ]; then
  echo "NOTE: GCP cost-ops configs active: ${cost_ops_configs[*]} — use the gcloud-cost-ops skill (.claude/skills/gcloud-cost-ops/gcp-ops.sh); the default config stays empty and unprivileged."
else
  echo "NOTE: no GCP cost-ops config active — no GCP_COST_OPS_KEY_<ALIAS> secret found in this environment (see $RUNBOOK §2; a mistyped prefix is silently not a cost-ops key)."
fi
if [ "${#cost_ops_failed[@]}" -gt 0 ]; then
  echo "NOTE: GCP cost-ops activation FAILED for: ${cost_ops_failed[*]} (invalid or empty key? see $RUNBOOK)."
fi
