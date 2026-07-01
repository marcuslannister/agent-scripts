#!/usr/bin/env bash
set -euo pipefail

# Install/update the visual-explainer plugin for Codex.
# Keeps a persistent clone under ~/Projects (no /tmp), then links the skill into
# ~/.codex with a relative symlink so it tracks pulls, and copies prompt
# templates into ~/.codex/prompts. Re-runnable; exits non-zero on failure.
#
# ~/.codex is itself a symlink into ~/Projects, so the relative target
# ../visual-explainer/plugins/visual-explainer resolves to the ~/Projects clone.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/nicobailon/visual-explainer.git"
CLONE_DIR="${HOME}/Projects/visual-explainer"
PLUGIN_DIR="${CLONE_DIR}/plugins/visual-explainer"
SKILL_LINK="${HOME}/.codex/visual-explainer"
SKILL_TARGET="../visual-explainer/plugins/visual-explainer"
PROMPT_DEST="${HOME}/.codex/prompts"

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

section "Installing skill"
ln -snf "$SKILL_TARGET" "$SKILL_LINK"
info "skill -> $SKILL_LINK -> $SKILL_TARGET"

section "Installing prompt templates"
mkdir -p "$PROMPT_DEST"
if compgen -G "${PLUGIN_DIR}/commands/*.md" >/dev/null; then
  cp "${PLUGIN_DIR}"/commands/*.md "$PROMPT_DEST"/
  info "prompts -> $PROMPT_DEST"
else
  info "no command templates to copy"
fi

section "visual-explainer done"
