#!/usr/bin/env bash

CLAUDE_ROOT_STATE=
CLAUDE_ROOT_ACTION=
CLAUDE_ROOT_MESSAGE=
CLAUDE_ROOT_MIGRATED=0

claude_root_surface_path() { # home discovery_root
  if [ "${TOPOLOGY_CLAUDE_ROOT_LEGACY:-0}" = 1 ]; then
    printf '%s/claude-root-after-migration\n' "$2"
  else
    printf '%s/.claude/skills\n' "$1"
  fi
}

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

claude_root_make_backup_dir() { # home
  local home="$1" stamp base candidate suffix
  stamp="${AGENT_SCRIPTS_MIGRATION_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  base="$home/.claude/skills-migrated-$stamp"
  candidate="$base"
  suffix=1
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    candidate="$base-$suffix"
    suffix=$((suffix + 1))
  done
  mkdir -p "$home/.claude"
  mkdir "$candidate"
  printf '%s\n' "$candidate"
}

claude_root_needs_migration() {
  case "$CLAUDE_ROOT_STATE" in
    legacy-symlink|legacy-pointer) return 0 ;;
    *) return 1 ;;
  esac
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
  elif [ -f "$root" ]; then
    CLAUDE_ROOT_STATE=legacy-pointer
    CLAUDE_ROOT_ACTION=migrate
  elif [ -e "$root" ]; then
    CLAUDE_ROOT_MESSAGE="Claude skills root is not a directory: $root"
  else
    CLAUDE_ROOT_MESSAGE="Claude skills root is missing: $root"
  fi
}

claude_root_reconcile() { # repo_root home
  local repo_root="$1" home="$2" root backup destination
  root="$home/.claude/skills"
  claude_root_inspect "$repo_root" "$home"
  case "$CLAUDE_ROOT_STATE" in
    managed) return 0 ;;
    legacy-symlink)
      unlink "$root" || return 1
      ;;
    legacy-pointer)
      if ! backup="$(claude_root_make_backup_dir "$home")"; then
        printf 'could not create Claude-root migration backup under %s; legacy pointer preserved\n' "$home/.claude" >&2
        return 1
      fi
      destination="$backup/skills"
      if ! mv "$root" "$destination"; then
        printf 'could not migrate legacy Claude root %s; preserved in place\n' "$root" >&2
        return 1
      fi
      ;;
    *) printf '%s\n' "$CLAUDE_ROOT_MESSAGE" >&2; return 1 ;;
  esac
  mkdir -p "$root" || return 1
  printf 'claude-skills\n' > "$root/.agent-scripts-root" || return 1
  CLAUDE_ROOT_STATE=managed
  CLAUDE_ROOT_ACTION=migrated
  CLAUDE_ROOT_MIGRATED=1
}

claude_root_cleanup_legacy_copies() { # repo_root home registry plan changes errors
  local repo_root="$1" home="$2" registry="$3" plan="$4" changes="$5" errors="$6"
  local marker skill owner source_id desired replacement_owner failed=0 message
  [ "$CLAUDE_ROOT_MIGRATED" = 1 ] || return 0

  for marker in "$repo_root"/skills/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    skill="$(basename "$(dirname "$marker")")"
    owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    case "$owner" in cli-skills) source_id=matt-skills ;; *) source_id="$owner" ;; esac
    jq -e --arg source "$source_id" \
      'any(.[]; .sourceId == $source and (.classification == "source-only" or .classification == "npx-only"))' \
      "$registry" >/dev/null || continue

    if [ -n "$(git -C "$repo_root" ls-files -- "skills/$skill")" ]; then
      message="refusing to remove tracked legacy Claude copy: skills/$skill"
      jq -cn --arg message "$message" '$message' >> "$errors"
      failed=1
      continue
    fi

    desired=false
    if jq -e --arg source "$source_id" --arg skill "$skill" \
      'any(.[]; .sourceId == $source and .skill == $skill and (.destinations | index("claude") != null))' \
      "$plan" >/dev/null; then
      desired=true
    fi
    if [ "$desired" = true ]; then
      replacement_owner="$(sed -n '2p' "$home/.claude/skills/$skill/.agent-scripts-copy" 2>/dev/null || true)"
      if [ "$replacement_owner" != "$source_id" ]; then
        message="refusing to remove legacy Claude copy without verified replacement: $source_id/$skill"
        jq -cn --arg message "$message" '$message' >> "$errors"
        failed=1
        continue
      fi
    fi

    if ! rm -rf -- "$repo_root/skills/$skill"; then
      message="could not remove legacy Claude copy: $source_id/$skill"
      jq -cn --arg message "$message" '$message' >> "$errors"
      failed=1
      continue
    fi
    jq -cn --arg sourceId "$source_id" --arg skill "$skill" \
      '{action:"legacy-copy-removed",sourceId:$sourceId,skill:$skill,destination:"claude"}' >> "$changes"
  done
  return "$failed"
}
