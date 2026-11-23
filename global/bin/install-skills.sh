#!/usr/bin/env bash
# Copy the shared skills into each CLI's skills root as plain directories.
# The agent-scripts sync keeps unmarked directories and refuses symlinks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# copy_dir_replace: rsync --delete, or a fresh copy where rsync is missing (Git Bash).
source "$ROOT/../agent-tooling/lib-copies.sh"
for root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$root"
  for skill in "$ROOT"/skills/*/; do
    name="$(basename "$skill")"
    # The matrix distribution owns a symlink or a marked folder: keep it, install the rest.
    # shortcut: a same-name folder without a marker that the user made by hand is still replaced,
    # as with the manual installer before; upgrade: give the own skills their own marker.
    if [ -L "$root/$name" ] || [ -f "$root/$name/.agent-scripts-copy" ]; then
      copy_warn "skipping $root/$name: owned by the skills matrix distribution (a symlink or a folder with .agent-scripts-copy)"
      continue
    fi
    copy_dir_replace "${skill%/}" "$root/$name"
    # Codex ignores disable-model-invocation and reads policy in agents/openai.yaml (Pi and Claude Code read the SKILL.md field).
    # shortcut: only creates a missing agents/openai.yaml; an existing one is trusted, so a source file needs its own policy.
    if grep -q '^disable-model-invocation: *true' "$skill/SKILL.md" && [ ! -e "$root/$name/agents/openai.yaml" ]; then
      mkdir -p "$root/$name/agents"
      printf 'policy:\n  allow_implicit_invocation: false\n' > "$root/$name/agents/openai.yaml"
    fi
    printf 'installed %s -> %s\n' "$name" "$root/$name"
  done
done
