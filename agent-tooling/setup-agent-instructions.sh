#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_ROOT/AGENTS.MD"
CODEX_MD="$REPO_ROOT/AGENTS.codex.md"
RULES_DIR="$REPO_ROOT/rules"
CODEX_POINTER="$HOME/.codex/AGENTS.md"
changed=0

if [ ! -f "$AGENTS_MD" ]; then
  printf 'error: shared instruction file missing: %s\n' "$AGENTS_MD" >&2
  exit 1
fi
if [ ! -f "$CODEX_MD" ]; then
  printf 'error: generated Codex file missing: %s\nhint: run agent-tooling/build-codex-instructions.sh\n' "$CODEX_MD" >&2
  exit 1
fi

ensure_pointer() { # path target
  local pointer="$1"
  local want="$2"
  local target

  mkdir -p "$(dirname "$pointer")"
  # -L before -e: a dangling symlink fails -e but is still user state.
  if [ -L "$pointer" ]; then
    target="$(readlink "$pointer")"
    # Resolve both: a relative symlink to the same place is ours, not foreign.
    # A dangling one never resolves to $want, so it stays preserved.
    if [ "$(readlink -f "$pointer")" = "$(readlink -f "$want")" ]; then
      return 0
    fi
    printf 'warning: preserving foreign symlink: %s -> %s\n' "$pointer" "$target" >&2
    return 0
  fi
  if [ -e "$pointer" ]; then
    printf 'warning: preserving real file: %s\n' "$pointer" >&2
    return 0
  fi

  ln -s "$want" "$pointer"
  printf 'linked %s -> %s\n' "$pointer" "$want"
  changed=$((changed + 1))
}

# An earlier setup symlinked the Codex pointer to AGENTS.MD; resolving the
# target proves that one is ours, and since the split it leaves Codex with only
# a link list it cannot follow. A regular file is never ours to judge, so it is
# reported and left alone.
if [ -L "$CODEX_POINTER" ] && [ "$(readlink -f "$CODEX_POINTER")" = "$(readlink -f "$AGENTS_MD")" ]; then
  rm "$CODEX_POINTER"
  printf 'migrated legacy Codex symlink to the generated file\n'
  changed=$((changed + 1))
elif [ -f "$CODEX_POINTER" ] && [ ! -L "$CODEX_POINTER" ]; then
  printf 'warning: %s is a regular file; Codex may be reading stale rules\nhint: remove it and rerun to point Codex at %s\n' "$CODEX_POINTER" "$CODEX_MD" >&2
fi

ensure_pointer "$HOME/.claude/CLAUDE.md" "$AGENTS_MD"
ensure_pointer "$CODEX_POINTER" "$CODEX_MD"
# Pi resolves and opens the ~/.claude/rules links, verified against pi 0.84.2,
# so it reads the root file like Claude Code rather than the inlined build.
ensure_pointer "$HOME/.pi/agent/AGENTS.md" "$AGENTS_MD"
# Makes the ~/.claude/rules/*.md links in AGENTS.MD resolve from any cwd.
ensure_pointer "$HOME/.claude/rules" "$RULES_DIR"

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
