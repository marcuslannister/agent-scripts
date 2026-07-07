#!/usr/bin/env bash
set -euo pipefail

# Install/update visual-explainer for Codex only (Claude Code gets it as a
# marketplace plugin; the repo ships no Codex plugin and no npx installer).
# Keeps a persistent clone under ~/Projects (no /tmp), then rsyncs the plugin
# dir into Codex's user skill root as a COPY (never a symlink) so it does not
# pass through Claude Code.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_URL="https://github.com/nicobailon/visual-explainer.git"
CLONE_DIR="${HOME}/Projects/visual-explainer"
PLUGIN_DIR="${CLONE_DIR}/plugins/visual-explainer"
CODEX_SKILLS_DIR="${HOME}/.agents/skills"
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

section "Copying Codex skill"
if [ -L "$OLD_CODEX_LINK" ] && [ "$(readlink "$OLD_CODEX_LINK")" = "$OLD_CODEX_TARGET" ]; then
  unlink "$OLD_CODEX_LINK"
  info "removed stale $OLD_CODEX_LINK"
elif [ -f "$OLD_CODEX_LINK" ] && [ "$(cat "$OLD_CODEX_LINK")" = "$OLD_CODEX_TARGET" ]; then
  rm -f "$OLD_CODEX_LINK"
  info "removed stale $OLD_CODEX_LINK"
fi

# Codex surface has no .gitignore, so pass ""; owner-keyed cleanup now removes
# the copy if the plugin dir is ever renamed or dropped upstream.
if ! sync_skill_copies visual-explainer "${CLONE_DIR}/plugins" "$CODEX_SKILLS_DIR" "" \
  visual-explainer; then
  exit 1
fi

section "visual-explainer done"
