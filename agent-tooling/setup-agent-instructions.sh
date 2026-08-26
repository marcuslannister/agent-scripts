#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_ROOT/AGENTS.MD"
CODEX_MD="$REPO_ROOT/AGENTS.codex.md"
RULES_DIR="$REPO_ROOT/rules"
changed=0

if [ ! -f "$AGENTS_MD" ]; then
  printf 'error: shared instruction file missing: %s\n' "$AGENTS_MD" >&2
  exit 1
fi
if [ ! -f "$CODEX_MD" ]; then
  printf 'error: generated Codex file missing: %s\n' "$CODEX_MD" >&2
  printf 'hint: run agent-tooling/build-codex-instructions.sh\n' >&2
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
    if [ "$target" = "$want" ]; then
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

ensure_pointer "$HOME/.claude/CLAUDE.md" "$AGENTS_MD"
ensure_pointer "$HOME/.claude/AGENTS.md" "$AGENTS_MD"
ensure_pointer "$HOME/.codex/AGENTS.md" "$CODEX_MD"

# Per file, not a directory symlink: ~/.claude/rules may already hold unrelated
# user rules. This lets the relative rules/ links in AGENTS.MD resolve from the
# pointer's own directory, without a machine-specific path in the file.
for rule in "$RULES_DIR"/*.md; do
  [ -f "$rule" ] || continue
  ensure_pointer "$HOME/.claude/rules/$(basename "$rule")" "$rule"
done

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
