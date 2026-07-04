#!/usr/bin/env bash
set -euo pipefail

# Update Waza and refresh all skills.sh-managed agent skills.
# Bootstraps the Waza package (tw93/Waza) if missing, then runs the CLI's
# global update — which refreshes every skills.sh-managed package, including
# mattpocock/skills' canonical copies (its bootstrap and Claude-side copy sync
# live in update-mattpocock-skills.sh, which must run after this).
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

section "waza-skills done"
exit $fail
