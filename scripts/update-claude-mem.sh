#!/usr/bin/env bash
set -euo pipefail

# Install/update claude-mem (github.com/thedotmack/claude-mem) for Claude Code
# and Codex through each CLI's own plugin marketplace — no npx installer, so
# both tools manage it like any other marketplace plugin and share one worker
# and database (~/.claude-mem). Marketplace names come from the repo manifests:
# "thedotmack" (.claude-plugin/marketplace.json) for Claude Code and
# "claude-mem-local" (.agents/plugins/marketplace.json) for Codex.
# Re-runnable; exits non-zero on failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-plugins.sh"

update_dual_marketplace_plugin "thedotmack/claude-mem" thedotmack claude-mem-local claude-mem

plugins_section "claude-mem done"
