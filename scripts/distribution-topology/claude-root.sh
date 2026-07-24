#!/usr/bin/env bash

CLAUDE_ROOT_STATE=
CLAUDE_ROOT_ACTION=
CLAUDE_ROOT_MESSAGE=
CLAUDE_ROOT_MIGRATED=0

claude_root_canonical_path() { # path
  local candidate="$1" directory base
  directory="$(dirname "$candidate")"
  base="$(basename "$candidate")"
  if [ -d "$directory" ]; then
    (cd "$directory" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$candidate"
  fi
}

claude_root_inspect() { # repo_root home
  local repo_root="$1" home="$2" root target expected marker
  root="$home/.claude/skills"
  expected="$(claude_root_canonical_path "$repo_root/skills")"
  CLAUDE_ROOT_STATE=unexpected
  CLAUDE_ROOT_ACTION=blocked
  CLAUDE_ROOT_MESSAGE=

  if [ -L "$root" ]; then
    target="$(readlink "$root")"
    case "$target" in
      /*) ;;
      *) target="$(dirname "$root")/$target" ;;
    esac
    if [ -d "$target" ] && [ "$(claude_root_canonical_path "$target")" = "$expected" ]; then
      CLAUDE_ROOT_STATE=legacy-symlink
      CLAUDE_ROOT_ACTION=migrate
    else
      CLAUDE_ROOT_MESSAGE="Claude skills root is an unexpected symlink: $root"
    fi
  elif [ -d "$root" ]; then
    marker="$(sed -n '1p' "$root/.agent-scripts-root" 2>/dev/null || true)"
    if [ "$marker" = claude-skills ]; then
      CLAUDE_ROOT_STATE=managed
      CLAUDE_ROOT_ACTION=none
    else
      CLAUDE_ROOT_MESSAGE="Claude skills root is not managed by agent-scripts: $root"
    fi
  elif [ -e "$root" ]; then
    CLAUDE_ROOT_MESSAGE="Claude skills root is not a directory: $root"
  else
    CLAUDE_ROOT_MESSAGE="Claude skills root is missing: $root"
  fi
}

claude_root_reconcile() { # repo_root home
  local repo_root="$1" home="$2" root
  root="$home/.claude/skills"
  claude_root_inspect "$repo_root" "$home"
  case "$CLAUDE_ROOT_STATE" in
    managed) return 0 ;;
    legacy-symlink)
      unlink "$root" || return 1
      mkdir -p "$root" || return 1
      printf 'claude-skills\n' > "$root/.agent-scripts-root" || return 1
      CLAUDE_ROOT_STATE=managed
      CLAUDE_ROOT_ACTION=migrated
      CLAUDE_ROOT_MIGRATED=1
      ;;
    *) printf '%s\n' "$CLAUDE_ROOT_MESSAGE" >&2; return 1 ;;
  esac
}
