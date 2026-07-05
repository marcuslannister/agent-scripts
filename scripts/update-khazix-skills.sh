#!/usr/bin/env bash
set -euo pipefail

# Install/update KKKKhazix/khazix-skills (source-only repo).
# Keeps a persistent clone under ~/Projects, then rsyncs the neat-freak skill
# into this repo's skills/ as an untracked COPY (never a symlink). A
# marker-delimited block in .gitignore keeps the copy out of the repo.
# Re-runnable; exits non-zero on failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_URL="https://github.com/KKKKhazix/khazix-skills.git"
CLONE_DIR="${HOME}/Projects/khazix-skills"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
GITIGNORE="${REPO_ROOT}/.gitignore"

section "Repo (KKKKhazix/khazix-skills)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

if [ ! -f "${CLONE_DIR}/neat-freak/SKILL.md" ]; then
  warn "skill missing: ${CLONE_DIR}/neat-freak/SKILL.md"
  exit 1
fi

section "Copying skill"
install_skill_copy "${CLONE_DIR}/neat-freak" "${SKILLS_DIR}/neat-freak"
info "skill copied -> ${SKILLS_DIR}/neat-freak"

regen_gitignore_block "$GITIGNORE" "khazix-skills" "update-khazix-skills.sh" \
  "skills/neat-freak"
info "regenerated khazix-skills block in .gitignore"

section "khazix-skills done"
