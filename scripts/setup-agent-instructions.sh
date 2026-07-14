#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_ROOT/AGENTS.MD"
changed=0

if [ ! -f "$AGENTS_MD" ]; then
  printf 'error: shared instruction file missing: %s\n' "$AGENTS_MD" >&2
  exit 1
fi

ensure_pointer() { # path
  local pointer="$1"
  local target

  mkdir -p "$(dirname "$pointer")"
  if [ -L "$pointer" ]; then
    target="$(readlink "$pointer")"
    if [ "$target" = "$AGENTS_MD" ]; then
      return 0
    fi
    printf 'warning: preserving foreign symlink: %s -> %s\n' "$pointer" "$target" >&2
    return 0
  fi
  if [ -e "$pointer" ]; then
    printf 'warning: preserving real file: %s\n' "$pointer" >&2
    return 0
  fi

  ln -s "$AGENTS_MD" "$pointer"
  printf 'linked %s -> %s\n' "$pointer" "$AGENTS_MD"
  changed=$((changed + 1))
}

ensure_pointer "$HOME/.claude/CLAUDE.md"
ensure_pointer "$HOME/.claude/AGENTS.md"
ensure_pointer "$HOME/.codex/AGENTS.md"

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
