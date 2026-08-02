#!/usr/bin/env bash
set -euo pipefail

# Update the coding-agent CLIs: Claude Code (native) + Codex (npm).
# Tries both even if one fails; exits non-zero if any update failed.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

fail=0

section "Claude Code CLI"
if ! command -v claude >/dev/null 2>&1; then
  info "claude not found; installing"
  if curl -fsSL https://claude.ai/install.sh | bash && command -v claude >/dev/null 2>&1; then
    info "installed: $(claude --version 2>/dev/null || echo unknown)"
  else
    warn "claude install failed"
    fail=1
  fi
else
  info "current: $(claude --version 2>/dev/null || echo unknown)"
  if claude update; then
    info "now:     $(claude --version 2>/dev/null || echo unknown)"
  else
    warn "claude update failed"
    fail=1
  fi
fi

section "Codex CLI"
if ! command -v codex >/dev/null 2>&1; then
  info "codex not found; installing"
  if npm install -g @openai/codex && command -v codex >/dev/null 2>&1; then
    info "installed: $(codex --version 2>/dev/null || echo unknown)"
  else
    warn "codex install failed"
    fail=1
  fi
else
  current_codex="$(codex --version 2>/dev/null || echo unknown)"
  current_codex_version="${current_codex##* }"
  latest_codex_version="$(npm view @openai/codex version 2>/dev/null || true)"
  latest_codex_version="${latest_codex_version//$'\r'/}"
  info "current: $current_codex"
  if [ -n "$latest_codex_version" ] && [ "$current_codex_version" = "$latest_codex_version" ]; then
    info "latest:  $latest_codex_version"
    info "codex already up to date; skipping npm install"
    info "now:     $(codex --version 2>/dev/null || echo unknown)"
  elif npm install -g @openai/codex; then
    info "now:     $(codex --version 2>/dev/null || echo unknown)"
  else
    warn "codex update failed"
    fail=1
  fi
fi

section "Agent CLIs done"
exit $fail
