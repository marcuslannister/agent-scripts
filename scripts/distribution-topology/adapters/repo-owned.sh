#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"

case "$source_id" in
  repo-claude) source_relative=skills ;;
  repo-codex) source_relative=codex-skills ;;
  *)
    echo "unknown repo-owned source: $source_id" >&2
    exit 1
    ;;
esac

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
