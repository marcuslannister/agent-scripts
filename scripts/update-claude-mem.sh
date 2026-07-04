#!/usr/bin/env bash
set -euo pipefail

# Install/update claude-mem (github.com/thedotmack/claude-mem) for Claude Code
# and Codex through each CLI's own plugin marketplace — no npx installer, so
# both tools manage it like any other marketplace plugin and share one worker
# and database (~/.claude-mem). Marketplace names come from the repo manifests:
# "thedotmack" (.claude-plugin/marketplace.json) for Claude Code and
# "claude-mem-local" (.agents/plugins/marketplace.json) for Codex.
# Re-runnable; exits non-zero on failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO="thedotmack/claude-mem"

codex_marketplace_upgrade() {
  local marketplace="$1"
  local attempt

  for attempt in 1 2 3; do
    if codex plugin marketplace upgrade "$marketplace"; then
      return 0
    fi
    [ "$attempt" -lt 3 ] || return 1
    warn "codex marketplace upgrade failed; retrying ($attempt/3)"
    sleep 2
  done
}

section "Claude Code (marketplace thedotmack)"
if claude plugin marketplace list 2>/dev/null | grep -q 'thedotmack'; then
  info "updating marketplace thedotmack"
  claude plugin marketplace update thedotmack
else
  info "adding marketplace thedotmack (${REPO})"
  claude plugin marketplace add "$REPO"
fi
if claude plugin list 2>/dev/null | grep -q 'claude-mem'; then
  info "updating plugin claude-mem@thedotmack"
  claude plugin update claude-mem@thedotmack
else
  info "installing plugin claude-mem@thedotmack"
  claude plugin install claude-mem@thedotmack
fi

section "Codex (marketplace claude-mem-local)"
if codex plugin marketplace list 2>/dev/null | grep -q 'claude-mem-local'; then
  info "upgrading marketplace claude-mem-local"
  codex_marketplace_upgrade claude-mem-local
else
  info "adding marketplace claude-mem-local (${REPO})"
  codex plugin marketplace add "$REPO"
fi
if codex plugin list -m claude-mem-local --json 2>/dev/null \
  | jq -e '.installed[]? | select(.pluginId == "claude-mem@claude-mem-local" and .installed == true and .enabled == true)' >/dev/null; then
  info "claude-mem@claude-mem-local already installed and enabled"
else
  info "installing plugin claude-mem@claude-mem-local"
  codex plugin add claude-mem@claude-mem-local
fi

section "claude-mem done"
