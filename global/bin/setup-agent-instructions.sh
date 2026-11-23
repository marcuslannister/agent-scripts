#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_ROOT/AGENTS.md"
CODEX_MD="$REPO_ROOT/AGENTS.codex.md"
RULES_DIR="$REPO_ROOT/rules"
CODEX_POINTER="$HOME/.codex/AGENTS.md"
PI_POINTER="$HOME/.pi/agent/AGENTS.md"
changed=0

if [ ! -f "$AGENTS_MD" ]; then
  printf 'error: shared instruction file missing: %s\n' "$AGENTS_MD" >&2
  exit 1
fi
if [ ! -f "$CODEX_MD" ]; then
  printf 'error: generated Codex file missing: %s\nhint: run bin/build-codex-instructions.sh\n' "$CODEX_MD" >&2
  exit 1
fi

ensure_pointer() { # path target [legacy-target]
  local pointer="$1"
  local want="$2"
  local legacy="${3:-}"
  local target link_dir want_rel

  mkdir -p "$(dirname "$pointer")"
  # Relative targets, computed from the physically resolved link directory,
  # because ~/.claude and ~/.pi are themselves symlinks into other checkouts.
  # Fall back to the absolute path where realpath cannot compute a relative one.
  link_dir="$(cd "$(dirname "$pointer")" && pwd -P)"
  want_rel="$(realpath --relative-to="$link_dir" "$want" 2>/dev/null || printf '%s' "$want")"

  # -L before -e: a dangling symlink fails -e but is still user state.
  if [ -L "$pointer" ]; then
    target="$(readlink "$pointer")"
    # Resolve both: a symlink to the same place is ours whatever its spelling.
    # A dangling one never resolves to $want, so it stays preserved.
    if [ "$(readlink -f "$pointer")" = "$(readlink -f "$want")" ]; then
      [ "$target" = "$want_rel" ] && return 0
      ln -snf "$want_rel" "$pointer"
      printf 'normalized %s -> %s\n' "$pointer" "$want_rel"
      changed=$((changed + 1))
      return 0
    fi
    # An earlier setup linked this pointer to $legacy. Resolving the target
    # proves the link is ours, so replace it in this step: a failure elsewhere
    # never leaves the pointer missing.
    if [ -n "$legacy" ] && [ "$(readlink -f "$pointer")" = "$(readlink -f "$legacy")" ]; then
      ln -snf "$want_rel" "$pointer"
      printf 'migrated legacy symlink %s -> %s\n' "$pointer" "$want_rel"
      changed=$((changed + 1))
      return 0
    fi
    printf 'warning: preserving foreign symlink: %s -> %s\n' "$pointer" "$target" >&2
    return 0
  fi
  if [ -e "$pointer" ]; then
    printf 'warning: preserving real file: %s\n' "$pointer" >&2
    return 0
  fi

  ln -s "$want_rel" "$pointer"
  printf 'linked %s -> %s\n' "$pointer" "$want_rel"
  changed=$((changed + 1))
}

# A regular file is never ours to judge, so it is reported and left alone.
if [ -f "$CODEX_POINTER" ] && [ ! -L "$CODEX_POINTER" ]; then
  printf 'warning: %s is a regular file; Codex may be reading stale rules\nhint: remove it and rerun to point Codex at %s\n' "$CODEX_POINTER" "$CODEX_MD" >&2
fi

ensure_pointer "$HOME/.claude/CLAUDE.md" "$AGENTS_MD"
# Since the split, a legacy link to AGENTS.md leaves Codex with only a link list
# it cannot follow. Pi 1.5.2 never expands the @ imports in it either.
ensure_pointer "$CODEX_POINTER" "$CODEX_MD" "$AGENTS_MD"
ensure_pointer "$PI_POINTER" "$CODEX_MD" "$AGENTS_MD"
# Makes the ~/.claude/agent-rules/*.md links in AGENTS.md resolve from any cwd.
# Not ~/.claude/rules: Claude Code loads every file there at startup.
ensure_pointer "$HOME/.claude/agent-rules" "$RULES_DIR"
# Remove the pre-rename pointer only when it resolves to our rules directory.
OLD_RULES="$HOME/.claude/rules"
if [ -L "$OLD_RULES" ] && [ "$(readlink -f "$OLD_RULES")" = "$(readlink -f "$RULES_DIR")" ]; then
  rm "$OLD_RULES"
  printf 'removed legacy pointer %s\n' "$OLD_RULES"
  changed=$((changed + 1))
fi

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
