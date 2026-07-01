#!/usr/bin/env bash
set -euo pipefail

# Install/update the visual-explainer plugin for Codex.
# Keeps a persistent clone under ~/Projects (no /tmp); symlinks the skill so it
# tracks pulls, and copies prompt templates into ~/.codex (Codex reads them flat).
# Re-runnable; exits non-zero on failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

REPO_URL="https://github.com/nicobailon/visual-explainer.git"
CLONE_DIR="${HOME}/Projects/visual-explainer"
PLUGIN_DIR="${CLONE_DIR}/plugins/visual-explainer"
SKILL_DEST="${HOME}/.codex/skills/visual-explainer"
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
mkdir -p "$(dirname "$SKILL_DEST")"
rm -rf "$SKILL_DEST"
ln -s "$PLUGIN_DIR" "$SKILL_DEST"
info "skill -> $SKILL_DEST -> $PLUGIN_DIR"

section "Installing prompt templates"
mkdir -p "$PROMPT_DEST"
if compgen -G "${PLUGIN_DIR}/commands/*.md" >/dev/null; then
  cp "${PLUGIN_DIR}"/commands/*.md "$PROMPT_DEST"/
  info "prompts -> $PROMPT_DEST"
else
  info "no command templates to copy"
fi

section "visual-explainer done"
