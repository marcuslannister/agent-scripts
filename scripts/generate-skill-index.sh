#!/usr/bin/env bash
set -euo pipefail

# Generates INDEX.md from skill-authors.json, grouping every distributed skill
# by its true upstream author (see ADR-0003, issue #26). skills/ stays flat;
# this index is metadata, not a directory layout.
#
#   generate-skill-index.sh          rewrite INDEX.md
#   generate-skill-index.sh --check  fail if INDEX.md is stale (CI gate)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/skill-authors.json"
INDEX="$REPO_ROOT/INDEX.md"
SKILLS_DIR="$REPO_ROOT/skills"

mode=write
case "${1:-}" in
  --check) mode=check ;;
  "") ;;
  *) printf 'usage: %s [--check]\n' "$(basename "$0")" >&2; exit 2 ;;
esac

jq -e 'has("authorOrder") and (.skills | type == "object" and length > 0)' "$REGISTRY" >/dev/null \
  || { printf 'invalid registry: %s\n' "$REGISTRY" >&2; exit 1; }

# Every on-disk skill must be attributed, so a newly added repo skill can't
# silently escape the index.
missing=()
if [ -d "$SKILLS_DIR" ]; then
  while IFS= read -r skill_md; do
    name="$(basename "$(dirname "$skill_md")")"
    jq -e --arg n "$name" '.skills | has($n)' "$REGISTRY" >/dev/null || missing+=("$name")
  done < <(find "$SKILLS_DIR" -maxdepth 2 -name SKILL.md -type f | LC_ALL=C sort)
fi
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'skill(s) missing an author in %s: %s\n' "$REGISTRY" "${missing[*]}" >&2
  exit 1
fi

generate() {
  printf '# Skill author index\n\n'
  printf 'Generated from `skill-authors.json` by `scripts/generate-skill-index.sh` — do not edit by hand (`--check` gates freshness).\n\n'
  printf 'Every distributed skill grouped by true upstream author, independent of delivery mechanism (repo, synced copy, or plugin). See ADR-0003 and issue #26.\n'

  local authors author skill
  authors="$(jq -r '
    (.authorOrder) as $order
    | ([.skills[]] | unique) as $present
    | ($order + ($present - $order)) | .[]' "$REGISTRY")"

  while IFS= read -r author; do
    [ -n "$author" ] || continue
    local skills=()
    while IFS= read -r skill; do
      [ -n "$skill" ] && skills+=("$skill")
    done < <(jq -r --arg a "$author" '.skills | to_entries | map(select(.value == $a)) | .[].key' "$REGISTRY" | LC_ALL=C sort)
    [ "${#skills[@]}" -gt 0 ] || continue
    printf '\n## %s (%s)\n\n' "$author" "${#skills[@]}"
    for skill in "${skills[@]}"; do printf -- '- %s\n' "$skill"; done
  done <<< "$authors"
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
generate > "$tmp"

if [ "$mode" = check ]; then
  if ! diff -u "$INDEX" "$tmp" >/dev/null 2>&1; then
    printf 'INDEX.md is stale; run scripts/generate-skill-index.sh\n' >&2
    exit 1
  fi
  printf 'INDEX.md up to date\n'
else
  cp "$tmp" "$INDEX"
  printf 'wrote %s\n' "$INDEX"
fi
