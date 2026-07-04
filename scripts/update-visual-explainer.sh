#!/usr/bin/env bash
set -euo pipefail

# Install/update visual-explainer for Codex only.
# Keeps a persistent clone under ~/Projects (no /tmp), then links it into
# Codex's user skill root so it does not pass through Claude Code.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-links.sh"

REPO_URL="https://github.com/nicobailon/visual-explainer.git"
CLONE_DIR="${HOME}/Projects/visual-explainer"
PLUGIN_DIR="${CLONE_DIR}/plugins/visual-explainer"
CODEX_SKILLS_DIR="${HOME}/.agents/skills"
CODEX_LINK="${CODEX_SKILLS_DIR}/visual-explainer"
CODEX_TARGET="../../Projects/visual-explainer/plugins/visual-explainer"
OLD_CODEX_LINK="${HOME}/.codex/visual-explainer"
OLD_CODEX_TARGET="../Projects/visual-explainer/plugins/visual-explainer"

section "Repo (nicobailon/visual-explainer)"
if [ -d "${CLONE_DIR}/.git" ]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" pull --ff-only
else
  info "cloning into ${CLONE_DIR}"
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

if [ ! -d "$PLUGIN_DIR" ]; then
  warn "plugin dir missing: $PLUGIN_DIR"
  exit 1
fi

section "Installing Codex symlink"
if [ -L "$OLD_CODEX_LINK" ] && [ "$(readlink "$OLD_CODEX_LINK")" = "$OLD_CODEX_TARGET" ]; then
  unlink "$OLD_CODEX_LINK"
  info "removed stale $OLD_CODEX_LINK"
elif [ -f "$OLD_CODEX_LINK" ] && [ "$(cat "$OLD_CODEX_LINK")" = "$OLD_CODEX_TARGET" ]; then
  rm -f "$OLD_CODEX_LINK"
  info "removed stale $OLD_CODEX_LINK"
fi

mkdir -p "$CODEX_SKILLS_DIR"
if install_external_skill_link "$PLUGIN_DIR" "$CODEX_TARGET" "$CODEX_LINK"; then
  info "visual-explainer -> $CODEX_LINK -> $CODEX_TARGET"
else
  install_status=$?
  if [ "$install_status" -eq 2 ]; then
    info "visual-explainer -> $CODEX_LINK (copied from $PLUGIN_DIR; symlink unavailable)"
  else
    exit 1
  fi
fi

section "visual-explainer done"
