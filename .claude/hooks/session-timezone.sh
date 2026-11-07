#!/bin/bash
# SessionStart hook — put the session clock on Europe/Berlin (TBX-273).
#
# The session container runs UTC (/etc/localtime -> Etc/UTC, TZ unset), so every
# time a session prints — "deploy finished at", "timer armed for" — reads as UTC
# and has to be converted in the reader's head. Manuel works in Europe/Berlin.
#
# This sets TZ (not /etc/localtime): TZ is per-environment, explicit and
# inspectable, whereas /etc/localtime is container-global, root-owned and would
# silently shift every process that reads local time, app code under test
# included. Nothing about how the app *stores* time changes — the repo convention
# stays UTC DATETIME(6) in MySQL (CLAUDE.md, Conventions).
#
# TZ only fixes the container clock. The larger half — GitHub, Notion and Cloud
# Run timestamps, which come back UTC whatever TZ says — is a reporting
# convention, and lives in CLAUDE.md § Conventions. Scheduled-trigger cron is
# likewise evaluated UTC-side and TZ does not reach it.
#
# Design notes:
#   - Runs only in Claude Code on the web (CLAUDE_CODE_REMOTE=true); a no-op
#     locally, where the developer's own machine clock already applies.
#   - Defers to an existing TZ, so a web-environment variable or a deliberate
#     per-session override wins over this default.
#   - Degrades to UTC (the status quo) when tzdata lacks the zone; never fails a
#     session over a clock.
set -euo pipefail

log() { echo "[tz-hook] $*" >&2; }

# Only run in the remote (web) ephemeral environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ZONE="Europe/Berlin"

# An already-set TZ is someone's deliberate choice — leave it alone.
if [ -n "${TZ:-}" ]; then
  log "TZ already set to '$TZ'; leaving it."
  echo "NOTE: session clock is TZ=$TZ — \`date\` prints that zone, not UTC."
  exit 0
fi

if [ ! -e "/usr/share/zoneinfo/$ZONE" ]; then
  log "tzdata has no $ZONE; leaving the session on UTC."
  exit 0
fi

export TZ="$ZONE"
if [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -q '^export TZ=' "$CLAUDE_ENV_FILE" 2>/dev/null; then
  echo "export TZ=\"$ZONE\"" >> "$CLAUDE_ENV_FILE"
fi

log "Session clock set to $ZONE."
# One stdout line so the session context knows the clock already reads local:
# without it, `date` output (CEST) gets converted a second time on the way to
# the user, which is the very error this hook exists to remove.
echo "NOTE: session clock is TZ=$ZONE — \`date\` prints CET/CEST, not UTC; report times as printed and do not convert again."
