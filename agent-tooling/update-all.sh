#!/usr/bin/env bash
set -uo pipefail

# Top-level updater: agent CLIs, acquire, matrix refresh, then offline distribute.
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
acquire_status=0
matrix_status=0
distribute_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Acquiring skill topology"
"$SCRIPT_DIR/update-skill-topology.sh" || acquire_status=$?

section "Refreshing skills matrix"
"$SCRIPT_DIR/generate-skills-matrix.sh" > "$SCRIPT_DIR/skills-matrix.md.tmp" \
  && mv "$SCRIPT_DIR/skills-matrix.md.tmp" "$SCRIPT_DIR/skills-matrix.md" \
  || matrix_status=$?

section "Distributing skill surfaces"
"$SCRIPT_DIR/sync-skill-surfaces.sh" || distribute_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "skill acquire" "$acquire_status"
status_line "skills matrix" "$matrix_status"
status_line "skill distribute" "$distribute_status"

(( agents_status != 0 || acquire_status != 0 || matrix_status != 0 || distribute_status != 0 )) && exit 1
exit 0
