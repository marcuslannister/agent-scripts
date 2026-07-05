#!/usr/bin/env bash
set -euo pipefail

# Install/update Waza (github.com/tw93/Waza) for Claude Code and Codex through
# each CLI's own plugin marketplace — the umbrella "waza" plugin registers all
# eight skills namespaced as /waza:think, /waza:check, etc. Marketplace name is
# "waza" on both sides (.claude-plugin/marketplace.json and
# .agents/plugins/marketplace.json in the repo).
# Re-runnable; exits non-zero on failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-plugins.sh"

update_dual_marketplace_plugin "tw93/Waza" waza waza waza

plugins_section "waza done"
