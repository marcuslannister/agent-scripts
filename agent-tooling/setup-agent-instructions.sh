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

# Codex has no import syntax and does not reliably open a file it is only
# linked to, so it gets a flattened build with rules/ inlined. Claude Code
# follows the links, so it keeps the symlink.
build_flat() {
  cat "$AGENTS_MD"
  local rule
  for rule in "$REPO_ROOT"/rules/*.md; do
    [ -f "$rule" ] || continue
    printf '\n'
    cat "$rule"
  done
}

ensure_flat() { # path
  local dest="$1"
  local tmp

  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  build_flat >"$tmp"

  if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    cp "$dest" "$dest.$(date +%Y%m%d%H%M%S).bak"
    printf 'backed up %s\n' "$dest"
  fi
  rm -f "$dest"
  mv "$tmp" "$dest"
  printf 'built %s (flattened, %s bytes)\n' "$dest" "$(wc -c <"$dest" | tr -d ' ')"
  changed=$((changed + 1))
}

ensure_pointer "$HOME/.claude/CLAUDE.md"
ensure_pointer "$HOME/.claude/AGENTS.md"
ensure_flat "$HOME/.codex/AGENTS.md"

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
