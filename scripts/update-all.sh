#!/usr/bin/env bash
set -uo pipefail

# Top-level updater: agent CLIs + Claude Code plugins + agent skills.
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
plugins_status=0
cli_skills_status=0
visual_explainer_status=0
khazix_skills_status=0
anthropic_skills_status=0
claude_mem_status=0
waza_status=0
mattpocock_skills_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Updating Claude Code plugins"
"$SCRIPT_DIR/update-cc-plugins.sh" || plugins_status=$?

section "Updating cli-skills"
"$SCRIPT_DIR/update-cli-skills.sh" || cli_skills_status=$?

section "Updating visual-explainer"
"$SCRIPT_DIR/update-visual-explainer.sh" || visual_explainer_status=$?

section "Updating khazix-skills"
"$SCRIPT_DIR/update-khazix-skills.sh" || khazix_skills_status=$?

section "Updating anthropic-skills"
"$SCRIPT_DIR/update-anthropic-skills.sh" || anthropic_skills_status=$?

section "Updating claude-mem"
"$SCRIPT_DIR/update-claude-mem.sh" || claude_mem_status=$?

section "Updating waza"
"$SCRIPT_DIR/update-waza.sh" || waza_status=$?

section "Updating mattpocock-skills"
"$SCRIPT_DIR/update-mattpocock-skills.sh" || mattpocock_skills_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "Claude plugins" "$plugins_status"
status_line "cli-skills" "$cli_skills_status"
status_line "visual-explainer" "$visual_explainer_status"
status_line "khazix-skills" "$khazix_skills_status"
status_line "anthropic-skills" "$anthropic_skills_status"
status_line "claude-mem" "$claude_mem_status"
status_line "waza" "$waza_status"
status_line "mattpocock-skills" "$mattpocock_skills_status"

(( agents_status != 0 || plugins_status != 0 || cli_skills_status != 0 || visual_explainer_status != 0 || khazix_skills_status != 0 || anthropic_skills_status != 0 || claude_mem_status != 0 || waza_status != 0 || mattpocock_skills_status != 0 )) && exit 1
exit 0
