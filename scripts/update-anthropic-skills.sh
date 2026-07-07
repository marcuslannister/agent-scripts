#!/usr/bin/env bash
set -euo pipefail

# Install/update anthropics/skills (source-only repo).
# Keeps a persistent clone under ~/Projects (dir renamed anthropic-skills since
# the repo is just "skills"), then rsyncs selected skills into this repo's
# skills/ as untracked COPIES (never symlinks); a marker-delimited block in
# .gitignore keeps them out of the repo. The document skills also copy into
# ~/.agents/skills so Codex can discover them from its single active surface.
# frontend-design and skill-creator copy into ~/.agents/skills only: Claude
# Code ships both via plugins and does not read ~/.agents/skills, so Codex gets
# them without duplicating the plugins.
# Re-runnable; exits non-zero on failure.
#
# With --check-updates: pull the clone and report drift (upstream changed, or a
# local copy was hand-edited) for both surfaces without touching any copy.
# Exits non-zero when a sync is warranted, so it works as a gate.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_URL="https://github.com/anthropics/skills.git"
CLONE_DIR="${HOME}/Projects/anthropic-skills"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
GITIGNORE="${REPO_ROOT}/.gitignore"
SKILLS=(docx xlsx pdf pptx)
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"
AGENTS_SKILLS=("${SKILLS[@]}" frontend-design skill-creator)

CHECK_ONLY=0
[ "${1:-}" = "--check-updates" ] && CHECK_ONLY=1

section "Repo (anthropics/skills)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

failed=0

if [ "$CHECK_ONLY" -eq 1 ]; then
  # Both surfaces copy from the same clone, so docx/xlsx/pdf/pptx report once
  # per surface — that's intentional: a copy can drift on one surface only.
  section "Checking Claude surface"
  check_skill_copy_updates "${CLONE_DIR}/skills" "$SKILLS_DIR" anthropic-skills \
    "${SKILLS[@]}" || failed=1
  section "Checking Codex surface"
  check_skill_copy_updates "${CLONE_DIR}/skills" "$AGENTS_SKILLS_DIR" anthropic-skills \
    "${AGENTS_SKILLS[@]}" || failed=1
  if [ "$failed" -eq 0 ]; then
    section "anthropic-skills up to date"
  else
    section "anthropic-skills: sync needed (run without --check-updates to apply)"
  fi
  exit "$failed"
fi

section "Copying shared skills (Claude surface)"
if ! sync_skill_copies anthropic-skills "${CLONE_DIR}/skills" "$SKILLS_DIR" "$GITIGNORE" \
  "${SKILLS[@]}"; then
  failed=1
fi

section "Copying Codex surface skills"
# Same owner, second surface; the Codex surface has no .gitignore, so pass "".
if ! sync_skill_copies anthropic-skills "${CLONE_DIR}/skills" "$AGENTS_SKILLS_DIR" "" \
  "${AGENTS_SKILLS[@]}"; then
  failed=1
fi

[ "$failed" -eq 0 ] || exit 1
section "anthropic-skills done"
