#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"

case "$source_id" in
  repo-claude) source_relative=skills ;;
  repo-codex) source_relative=codex-skills ;;
  *)
    echo "unknown repo-owned source: $source_id" >&2
    exit 1
    ;;
esac

canonical_path() {
  local candidate="$1"
  local directory base
  directory="$(dirname "$candidate")"
  base="$(basename "$candidate")"
  if [ -d "$directory" ]; then
    (cd "$directory" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$candidate"
  fi
}

destination_path_for() {
  case "$1" in
    claude) printf '%s/skills/%s\n' "$repo_root" "$2" ;;
    codex) printf '%s/.agents/skills/%s\n' "$home" "$2" ;;
    *) return 1 ;;
  esac
}

case "$action" in
  discover)
    # Reserved for adapters that need isolated remote discovery.
    : "$discovery_root"
    git -C "$repo_root" ls-files -z -- "$source_relative" |
      while IFS= read -r -d '' tracked_path; do
        case "$tracked_path" in
          "$source_relative"/*/SKILL.md)
            relative_path="${tracked_path#"$source_relative"/}"
            skill_name="${relative_path%/SKILL.md}"
            case "$skill_name" in */*) continue ;; esac
            [ -f "$repo_root/$tracked_path" ] || continue
            printf '%s\n' "$skill_name"
            ;;
        esac
      done |
      LC_ALL=C sort
    ;;
  reconcile)
    plan_path="${5:?reconcile plan required}"
    home="${6:?home required}"
    source "$repo_root/scripts/lib-copies.sh"
    failed=0

    while IFS=$'\t' read -r operation skill destination; do
      [ -n "$operation" ] || continue
      case "$skill" in
        ''|*[!a-z0-9-]*) echo "invalid repo-owned skill name: $skill" >&2; failed=1; continue ;;
      esac
      case "$destination" in
        claude|codex) ;;
        *) echo "invalid repo-owned destination: $destination" >&2; failed=1; continue ;;
      esac
      if [ "$source_id" = repo-codex ] && [ "$destination" = claude ]; then
        echo "Codex authoring source cannot target Claude: $skill" >&2
        failed=1
        continue
      fi

      source_path="$repo_root/$source_relative/$skill"
      destination_path="$(destination_path_for "$destination" "$skill")"

      case "$operation" in
        install)
          if install_skill_copy "$source_path" "$destination_path" repo-skills >/dev/null; then
            printf 'installed\t%s\t%s\n' "$skill" "$destination"
          else
            failed=1
          fi
          ;;
        remove)
          marker="$destination_path/.agent-scripts-copy"
          marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
          if [ "$marker_owner" != repo-skills ]; then
            echo "refusing to remove unowned copy: $skill -> $destination" >&2
            failed=1
          elif rm -rf -- "$destination_path"; then
            printf 'removed\t%s\t%s\n' "$skill" "$destination"
          else
            failed=1
          fi
          ;;
        *)
          echo "unknown repo-owned reconcile operation: $operation" >&2
          failed=1
          ;;
      esac
    done < "$plan_path"
    exit "$failed"
    ;;
  verify)
    plan_path="${5:?verification plan required}"
    home="${6:?home required}"
    source "$repo_root/scripts/lib-copies.sh"
    failed=0

    while IFS=$'\t' read -r expected_state skill destination; do
      [ -n "$expected_state" ] || continue
      source_path="$repo_root/$source_relative/$skill"
      if ! destination_path="$(destination_path_for "$destination" "$skill")"; then
        echo "invalid repo-owned verification destination: $destination" >&2
        failed=1
        continue
      fi
      if [ "$source_id" = repo-codex ] && [ "$destination" = claude ]; then
        echo "Codex authoring source cannot target Claude: $skill" >&2
        failed=1
        continue
      fi
      marker="$destination_path/.agent-scripts-copy"
      marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"

      case "$expected_state" in
        present)
          marker_source="$(sed -n '1p' "$marker" 2>/dev/null || true)"
          case "$marker_source" in
            /*) recorded_source="$marker_source" ;;
            *) recorded_source="$repo_root/$marker_source" ;;
          esac
          recorded_source="$(canonical_path "$recorded_source")"
          expected_source="$(canonical_path "$source_path")"
          stored_hash="$(sed -n '3p' "$marker" 2>/dev/null || true)"
          source_hash="$(compute_copy_hash "$source_path" 2>/dev/null || true)"
          copy_hash="$(compute_copy_hash "$destination_path" 2>/dev/null || true)"
          if [ "$marker_owner" != repo-skills ] \
            || [ "$recorded_source" != "$expected_source" ] \
            || [ -z "$stored_hash" ] \
            || [ "$stored_hash" != "$source_hash" ] \
            || [ "$stored_hash" != "$copy_hash" ]; then
            echo "managed copy verification failed: $skill -> $destination" >&2
            failed=1
          fi
          ;;
        absent)
          if [ "$marker_owner" = repo-skills ]; then
            echo "retired repo-skills copy remains: $skill -> $destination" >&2
            failed=1
          fi
          ;;
        *)
          echo "invalid repo-owned verification state: $expected_state" >&2
          failed=1
          ;;
      esac
    done < "$plan_path"
    exit "$failed"
    ;;
  *)
    echo "unknown repo-owned adapter action: $action" >&2
    exit 1
    ;;
esac
