#!/usr/bin/env bash
set -uo pipefail

# Top-level updater: agent CLIs, then manifest-owned skill topology.
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
topology_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Updating skill topology"
"$SCRIPT_DIR/update-skill-topology.sh" || topology_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "skill topology" "$topology_status"

(( agents_status != 0 || topology_status != 0 )) && exit 1
exit 0
