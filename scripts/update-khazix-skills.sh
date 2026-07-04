#!/usr/bin/env bash
set -euo pipefail

# Install/update KKKKhazix/khazix-skills.
# Keeps a persistent clone under ~/Projects, then links the neat-freak skill
# into this repo's skills/ with a relative symlink so it tracks pulls.
# Re-runnable; exits non-zero on failure.
#
# skills/ lives at ~/Projects/agent-scripts/skills, so the relative target
# ../../khazix-skills/neat-freak reaches the ~/Projects clone.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-links.sh"

REPO_URL="https://github.com/KKKKhazix/khazix-skills.git"
CLONE_DIR="${HOME}/Projects/khazix-skills"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
SKILL_LINK="${SKILLS_DIR}/neat-freak"
SKILL_TARGET="../../khazix-skills/neat-freak"

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

section "Installing skill"
install_tracked_repo_symlink "$REPO_ROOT" "$SKILL_LINK" "$SKILL_TARGET"
info "skill -> $SKILL_LINK -> $SKILL_TARGET"

section "khazix-skills done"
