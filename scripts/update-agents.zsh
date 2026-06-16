#!/usr/bin/env zsh
set -euo pipefail

# Update the coding-agent CLIs: Claude Code (native) + Codex (npm).
# Tries both even if one fails; exits non-zero if any update failed.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

fail=0

section "Claude Code CLI"
info "current: $(claude --version 2>/dev/null || echo unknown)"
if claude update; then
  info "now:     $(claude --version 2>/dev/null || echo unknown)"
else
  warn "claude update failed"
  fail=1
fi

section "Codex CLI"
info "current: $(codex --version 2>/dev/null || echo unknown)"
if npm install -g @openai/codex; then
  info "now:     $(codex --version 2>/dev/null || echo unknown)"
else
  warn "codex update failed"
  fail=1
fi

section "Agent CLIs done"
exit $fail
