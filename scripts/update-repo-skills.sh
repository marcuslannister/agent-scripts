#!/usr/bin/env bash
set -euo pipefail

# Legacy bulk publisher for tracked repo skills. Root hygiene belongs to the
# topology command and intentionally does not run here. Re-runnable; exits
# non-zero on publication or active-copy verification failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"

fail=0

verify_tracked_codex_surface() { # tracked_names
  local tracked_names="$1"
  local name marker marker_source
  local verified=0
  local failed=0

  for name in $tracked_names; do
    marker="${AGENTS_SKILLS_DIR}/${name}/.agent-scripts-copy"
    if [ ! -f "${AGENTS_SKILLS_DIR}/${name}/SKILL.md" ]; then
      warn "tracked skill missing from active Codex surface: ${AGENTS_SKILLS_DIR}/${name}"
      failed=1
      continue
    fi
    if [ ! -f "$marker" ]; then
      warn "tracked skill missing Codex surface marker: ${AGENTS_SKILLS_DIR}/${name}"
      failed=1
      continue
    fi
    marker_source="$(sed -n '1p' "$marker")"
    if [ "$marker_source" != "${SKILLS_DIR}/${name}" ]; then
      warn "tracked skill marker mismatch for ${name}: ${marker_source}"
      failed=1
      continue
    fi
    verified=$((verified + 1))
  done

  if [ "$failed" -eq 0 ]; then
    info "verified ${verified} tracked marked copies on the Codex surface"
    return 0
  fi
  return 1
}

section "Repo skills → ~/.agents/skills (Codex surface)"

tracked="$(git -C "$REPO_ROOT" ls-files 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u)"
if [ -z "$tracked" ]; then
  warn "no tracked skills found under ${SKILLS_DIR}"
  exit 1
fi

mkdir -p "$AGENTS_SKILLS_DIR"
copied=0
for name in $tracked; do
  if install_skill_copy "${SKILLS_DIR}/${name}" "${AGENTS_SKILLS_DIR}/${name}" repo-skills; then
    copied=$((copied + 1))
  else
    fail=1
  fi
done
info "copied ${copied} tracked skills into ${AGENTS_SKILLS_DIR}"

if ! cleanup_marked_skill_copies "$AGENTS_SKILLS_DIR" repo-skills $tracked; then
  fail=1
fi

if ! verify_tracked_codex_surface "$tracked"; then
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
section "repo-skills done"
