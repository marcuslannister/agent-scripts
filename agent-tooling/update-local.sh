#!/usr/bin/env bash
set -uo pipefail

# Local (non-main-machine) updater: agent CLIs, then offline distribute only.
# No acquire/matrix step — this machine pulls already-committed staging
# changes via git and just reconciles local surfaces from them (ADR-0005).
# Runs every step (no fail-fast), prints a summary, exits non-zero on any failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section()     { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
status_line() { # name code
  if [ "$2" -eq 0 ]; then
    printf '\033[0;32m✓\033[0m %s\n' "$1"
  else
    printf '\033[0;31m✗\033[0m %s\n' "$1"
  fi
}

agents_status=0
distribute_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Distributing skill surfaces"
"$SCRIPT_DIR/sync-skill-surfaces.sh" || distribute_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "skill distribute" "$distribute_status"

(( agents_status != 0 || distribute_status != 0 )) && exit 1
exit 0
