#!/usr/bin/env bash
set -euo pipefail

# Install/update anthropics/skills.
# Keeps a persistent clone under ~/Projects (dir renamed anthropic-skills since
# the repo is just "skills"), then links selected skills into this repo's
# skills/ with relative symlinks so they track pulls.
# Re-runnable; exits non-zero on failure.
#
# skills/ lives at ~/Projects/agent-scripts/skills, so the relative target
# ../../anthropic-skills/skills/<name> reaches the ~/Projects clone.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/anthropics/skills.git"
CLONE_DIR="${HOME}/Projects/anthropic-skills"
SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
SKILLS=(frontend-design docx xlsx pdf pptx skill-creator)

section "Repo (anthropics/skills)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

section "Installing skills"
failed=0
for skill in "${SKILLS[@]}"; do
  if [ ! -f "${CLONE_DIR}/skills/${skill}/SKILL.md" ]; then
    warn "skill missing: ${CLONE_DIR}/skills/${skill}/SKILL.md"
    failed=1
    continue
  fi
  ln -snf "../../anthropic-skills/skills/${skill}" "${SKILLS_DIR}/${skill}"
  info "skill -> ${SKILLS_DIR}/${skill} -> ../../anthropic-skills/skills/${skill}"
done

[ "$failed" -eq 0 ] || exit 1
section "anthropic-skills done"
