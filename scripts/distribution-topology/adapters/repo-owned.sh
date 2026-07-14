#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"

case "$source_id" in
  repo-claude) source_root="$repo_root/skills" ;;
  repo-codex) source_root="$repo_root/codex-skills" ;;
  *)
    echo "unknown repo-owned source: $source_id" >&2
    exit 1
    ;;
esac

# Reserved for adapters that need isolated remote discovery.
: "$discovery_root"

if [ ! -d "$source_root" ]; then
  exit 0
fi

for candidate in "$source_root"/*; do
  [ -f "$candidate/SKILL.md" ] || continue
  basename "$candidate"
done | LC_ALL=C sort
