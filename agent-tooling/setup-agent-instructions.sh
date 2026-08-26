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
    # Compare resolved paths: a relative symlink to the same place is ours, not
    # foreign. A dangling one never resolves to $want, so it stays preserved.
    if [ "$target" = "$want" ] || [ "$(readlink -f "$pointer")" = "$(readlink -f "$want")" ]; then
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

# Earlier setups owned ~/.codex/AGENTS.md in two other shapes: a symlink to
# AGENTS.MD, and a generated regular file. Both are ours, so ensure_pointer
# would wrongly preserve them as user state and leave Codex on stale or
# link-only rules. Clear the ones we can prove we wrote; back up before any
# delete, and leave anything unrecognized alone.
migrate_codex_pointer() {
  local pointer="$HOME/.codex/AGENTS.md"

  if [ -L "$pointer" ]; then
    if [ "$(readlink -f "$pointer")" = "$(readlink -f "$AGENTS_MD")" ]; then
      rm "$pointer"
      printf 'migrated legacy Codex symlink to the generated file\n'
      changed=$((changed + 1))
    fi
    return 0
  fi
  [ -f "$pointer" ] || return 0

  case "$(head -n 1 "$pointer")" in
    *'build-codex-instructions.sh'* | 'Global agent rules'*) ;;
    *)
      printf 'warning: %s is not a recognized generated file; Codex may be reading stale rules\n' "$pointer" >&2
      printf 'hint: remove it and rerun to point Codex at %s\n' "$CODEX_MD" >&2
      return 0
      ;;
  esac

  cp "$pointer" "$pointer.$(date +%Y%m%d%H%M%S).bak"
  rm "$pointer"
  printf 'migrated generated Codex file (backup kept)\n'
  changed=$((changed + 1))
}

migrate_codex_pointer

ensure_pointer "$HOME/.claude/CLAUDE.md" "$AGENTS_MD"
ensure_pointer "$HOME/.claude/AGENTS.md" "$AGENTS_MD"
ensure_pointer "$HOME/.codex/AGENTS.md" "$CODEX_MD"
# Makes the ~/.claude/rules/*.md links in AGENTS.MD resolve from any cwd.
ensure_pointer "$HOME/.claude/rules" "$RULES_DIR"

[ "$changed" -ne 0 ] || printf 'instruction pointers up to date\n'
