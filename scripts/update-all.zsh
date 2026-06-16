#!/usr/bin/env zsh
set -uo pipefail

# Top-level updater: agent CLIs + Claude Code plugins.
# Runs every step (no fail-fast), prints a summary, exits non-zero on any failure.

SCRIPT_DIR=${0:A:h}

section()     { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
status_line() { # name code
  if [ "$2" -eq 0 ]; then
    printf '\033[0;32m✓\033[0m %s\n' "$1"
  else
    printf '\033[0;31m✗\033[0m %s\n' "$1"
  fi
}

agents_status=0
plugins_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.zsh" || agents_status=$?

section "Updating Claude Code plugins"
"$SCRIPT_DIR/update-cc-plugins.sh" || plugins_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "Claude plugins" "$plugins_status"

(( agents_status != 0 || plugins_status != 0 )) && exit 1
exit 0
