#!/usr/bin/env bash
set -euo pipefail

# Install/update anthropics/skills (source-only repo).
# Keeps a persistent clone under ~/Projects (dir renamed anthropic-skills since
# the repo is just "skills"), then rsyncs selected skills into this repo's
# skills/ as untracked COPIES (never symlinks); a marker-delimited block in
# .gitignore keeps them out of the repo. frontend-design and skill-creator copy
# into ~/.agents/skills instead (Codex-only, like visual-explainer): Claude
# Code ships both via plugins and does not read ~/.agents/skills, so Codex
# gets them without duplicating the plugins.
# Re-runnable; exits non-zero on failure.

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
AGENTS_SKILLS=(frontend-design skill-creator)

section "Repo (anthropics/skills)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

section "Copying shared skills"
failed=0
ignore_entries=()
for skill in "${SKILLS[@]}"; do
  if [ ! -f "${CLONE_DIR}/skills/${skill}/SKILL.md" ]; then
    warn "skill missing: ${CLONE_DIR}/skills/${skill}/SKILL.md"
    failed=1
  elif ! install_skill_copy "${CLONE_DIR}/skills/${skill}" "${SKILLS_DIR}/${skill}"; then
    failed=1
  else
    info "skill copied -> ${SKILLS_DIR}/${skill}"
  fi
  # Keep ignoring an existing copy even when this run's sync failed, so a
  # transient failure can't surface third-party files as trackable.
  if [ -d "${SKILLS_DIR}/${skill}" ]; then
    ignore_entries+=("skills/${skill}")
  fi
done
if ! cleanup_marked_skill_copies "$SKILLS_DIR" "${CLONE_DIR}/skills" "${SKILLS[@]}"; then
  failed=1
fi

regen_gitignore_block "$GITIGNORE" "anthropic-skills" "update-anthropic-skills.sh" \
  ${ignore_entries[@]+"${ignore_entries[@]}"}
info "regenerated anthropic-skills block in .gitignore"

section "Copying Codex-only skills"
mkdir -p "$AGENTS_SKILLS_DIR"
for skill in "${AGENTS_SKILLS[@]}"; do
  if [ ! -f "${CLONE_DIR}/skills/${skill}/SKILL.md" ]; then
    warn "skill missing: ${CLONE_DIR}/skills/${skill}/SKILL.md"
    failed=1
    continue
  fi
  if ! install_skill_copy "${CLONE_DIR}/skills/${skill}" "${AGENTS_SKILLS_DIR}/${skill}"; then
    failed=1
    continue
  fi
  info "skill copied -> ${AGENTS_SKILLS_DIR}/${skill}"
done
if ! cleanup_marked_skill_copies "$AGENTS_SKILLS_DIR" "${CLONE_DIR}/skills" "${AGENTS_SKILLS[@]}"; then
  failed=1
fi

[ "$failed" -eq 0 ] || exit 1
section "anthropic-skills done"
