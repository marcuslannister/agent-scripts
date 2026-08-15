#!/usr/bin/env bash
set -uo pipefail

# Secondary-machine updater (other Macs, Windows under Git Bash): fast-forward
# pull the repo, update agent CLIs, refresh native plugins best-effort, then
# distribute matrix-selected skills from tracked content (ADR-0009). No staging
# acquire — this machine pulls already-committed staging changes via git.
# Runs every step (no fail-fast), prints a summary, exits non-zero on failure.
#
# The pull happens before anything else and the script re-execs itself once
# afterwards, so a run always executes the freshly pulled version instead of a
# file that changed under the running interpreter.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

section()     { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()        { printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2; }
status_line() { # name code
  if [ "$2" -eq 0 ]; then
    printf '\033[0;32m✓\033[0m %s\n' "$1"
  else
    printf '\033[0;31m✗\033[0m %s\n' "$1"
  fi
}

pull_status="${AGENT_SCRIPTS_PULL_STATUS:-0}"
if [ -z "${AGENT_SCRIPTS_PULLED:-}" ]; then
  section "Pulling repository"
  if ! git -C "$REPO_ROOT" pull --ff-only; then
    pull_status=1
    warn "could not fast-forward the repository; continuing with local content"
  fi
  AGENT_SCRIPTS_PULLED=1 AGENT_SCRIPTS_PULL_STATUS="$pull_status" exec "$SCRIPT_DIR/update-local.sh" "$@"
fi

agents_status=0
plugins_status=0
distribute_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Refreshing native plugins"
"$SCRIPT_DIR/update-plugins.sh" || plugins_status=$?

section "Distributing skill surfaces"
"$SCRIPT_DIR/sync-skill-surfaces.sh" || distribute_status=$?

section "Summary"
status_line "repository pull" "$pull_status"
status_line "agent CLIs" "$agents_status"
status_line "native plugins" "$plugins_status"
status_line "skill distribute" "$distribute_status"

(( pull_status != 0 || agents_status != 0 || plugins_status != 0 || distribute_status != 0 )) && exit 1
exit 0
