#!/usr/bin/env bash

repo_owned_canonical_path() { # candidate
  local candidate="$1" directory base
  directory="$(dirname "$candidate")"
  base="$(basename "$candidate")"
  if [ -d "$directory" ]; then
    (cd "$directory" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$candidate"
  fi
}

repo_owned_source_path() { # repo_root source_id skill
  case "$2" in
    repo-claude) printf '%s/skills/%s\n' "$1" "$3" ;;
    repo-codex) printf '%s/codex-skills/%s\n' "$1" "$3" ;;
    *) return 1 ;;
  esac
}

repo_owned_destination_path() { # repo_root home destination skill
  case "$3" in
    claude) printf '%s/.claude/skills/%s\n' "$2" "$4" ;;
    codex) printf '%s/.agents/skills/%s\n' "$2" "$4" ;;
    *) return 1 ;;
  esac
}
