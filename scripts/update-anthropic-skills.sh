#!/usr/bin/env bash
set -euo pipefail

# Install/update anthropics/skills.
# Keeps a persistent clone under ~/Projects (dir renamed anthropic-skills since
# the repo is just "skills"), then links selected skills with relative symlinks
# so they track pulls: doc skills into this repo's skills/ (tracked),
# frontend-design + skill-creator into ~/Projects/codex-settings/skills
# (untracked here; Claude already ships those two via plugins).
# Re-runnable; exits non-zero on failure.
#
# Both link dirs sit at ~/Projects/<repo>/skills, so the relative target
# ../../anthropic-skills/skills/<name> reaches the ~/Projects clone from either.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/anthropics/skills.git"
CLONE_DIR="${HOME}/Projects/anthropic-skills"
REPO_SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
CODEX_SKILLS_DIR="${HOME}/Projects/codex-settings/skills"
REPO_SKILLS=(docx xlsx pdf pptx)
CODEX_SKILLS=(frontend-design skill-creator)

section "Repo (anthropics/skills)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

failed=0
link_skill() { # dest_dir name
  if [ ! -f "${CLONE_DIR}/skills/$2/SKILL.md" ]; then
    warn "skill missing: ${CLONE_DIR}/skills/$2/SKILL.md"
    failed=1
    return
  fi
  ln -snf "../../anthropic-skills/skills/$2" "$1/$2"
  info "skill -> $1/$2 -> ../../anthropic-skills/skills/$2"
}

section "Installing skills (repo)"
for skill in "${REPO_SKILLS[@]}"; do
  link_skill "$REPO_SKILLS_DIR" "$skill"
done

section "Installing skills (codex-settings)"
for skill in "${CODEX_SKILLS[@]}"; do
  link_skill "$CODEX_SKILLS_DIR" "$skill"
done

[ "$failed" -eq 0 ] || exit 1
section "anthropic-skills done"
