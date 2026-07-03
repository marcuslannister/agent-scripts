#!/usr/bin/env bash
set -euo pipefail

# Install/update anthropics/skills.
# Keeps a persistent clone under ~/Projects (dir renamed anthropic-skills since
# the repo is just "skills"), then links selected skills into this repo's
# skills/ with relative symlinks so they track pulls. frontend-design and
# skill-creator link into ~/.agents/skills instead (Codex-only, like
# visual-explainer): Claude Code ships both via plugins and does not read
# ~/.agents/skills, so Codex gets them without duplicating the plugins.
# Re-runnable; exits non-zero on failure.
#
# skills/ lives at ~/Projects/agent-scripts/skills, so the relative target
# ../../anthropic-skills/skills/<name> reaches the ~/Projects clone; from
# ~/.agents/skills it is ../../Projects/anthropic-skills/skills/<name>.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/anthropics/skills.git"
CLONE_DIR="${HOME}/Projects/anthropic-skills"
SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
SKILLS=(docx xlsx pdf pptx)
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"
AGENTS_SKILLS=(frontend-design skill-creator)

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

section "Installing Codex-only skills"
mkdir -p "$AGENTS_SKILLS_DIR"
for skill in "${AGENTS_SKILLS[@]}"; do
  if [ ! -f "${CLONE_DIR}/skills/${skill}/SKILL.md" ]; then
    warn "skill missing: ${CLONE_DIR}/skills/${skill}/SKILL.md"
    failed=1
    continue
  fi
  link="${AGENTS_SKILLS_DIR}/${skill}"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    warn "not a symlink, refusing to replace: $link"
    failed=1
    continue
  fi
  ln -snf "../../Projects/anthropic-skills/skills/${skill}" "$link"
  info "skill -> $link -> ../../Projects/anthropic-skills/skills/${skill}"
done

[ "$failed" -eq 0 ] || exit 1
section "anthropic-skills done"
