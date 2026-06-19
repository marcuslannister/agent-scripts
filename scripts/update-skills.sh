#!/usr/bin/env bash
set -euo pipefail

# Update skills.sh-managed agent skills (Waza et al.).
# Bootstraps the Waza package if missing, then refreshes all global skills.
# Exits non-zero if any step fails.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

LOCK="${HOME}/.agents/.skill-lock.json"

# The skills CLI prints "Failed to ..." lines but still exits 0 on partial
# failures (unreachable source, per-skill error). Treat those as failures too.
run_skills() { # args... -> streams output, returns 1 on any failure
  local out rc=0
  out="$(npx --yes skills@latest "$@" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'Failed to '; }
}

fail=0

section "Waza skills (tw93/Waza)"
if [ -f "$LOCK" ] && grep -q 'tw93/Waza' "$LOCK"; then
  info "already installed"
else
  info "installing"
  if run_skills add tw93/Waza --all --global --yes; then
    info "waza installed"
  else
    warn "waza install failed"
    fail=1
  fi
fi

section "Updating global skills"
if run_skills update --global --yes; then
  info "skills updated"
else
  warn "skills update failed"
  fail=1
fi

section "Agent skills done"
exit $fail
