#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"
mode="${7:-reconcile}"

source "$repo_root/scripts/lib-copies.sh"
source "${BASH_SOURCE[0]%/*}/copy-state.sh"

case "$source_id" in
  anthropic-skills)
    repo_url="https://github.com/anthropics/skills.git"
    clone_name="anthropic-skills"
    source_suffix="skills"
    owner="anthropic-skills"
    ;;
  khazix-skills)
    repo_url="https://github.com/KKKKhazix/khazix-skills.git"
    clone_name="khazix-skills"
    source_suffix=""
    owner="khazix-skills"
    ;;
  *)
    printf 'unknown copy source: %s\n' "$source_id" >&2
    exit 1
    ;;
esac

source_file="$discovery_root/$source_id.source-root"
marker_file="$discovery_root/$source_id.marker-root"

discover_source() {
  local clone_dir source_root marker_root skill_file skill count=0
  marker_root="$home/Projects/$clone_name"
  [ -n "$source_suffix" ] && marker_root="$marker_root/$source_suffix"
  if [ "$mode" = check ]; then
    clone_dir="$discovery_root/$source_id/repo"
  else
    clone_dir="$home/Projects/$clone_name"
  fi

  refresh_source_clone "$clone_dir" "$repo_url"
  source_root="$clone_dir"
  [ -n "$source_suffix" ] && source_root="$source_root/$source_suffix"
  [ -d "$source_root" ] || { printf 'source inventory root missing: %s\n' "$source_root" >&2; return 1; }
  printf '%s\n' "$source_root" > "$source_file"
  printf '%s\n' "$marker_root" > "$marker_file"

  for skill_file in "$source_root"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    skill="$(basename "$(dirname "$skill_file")")"
    case "$skill" in ''|*[!a-z0-9-]*) printf 'invalid source inventory skill: %s\n' "$skill" >&2; return 1 ;; esac
    if git -C "$repo_root" ls-files --error-unmatch -- "skills/$skill/SKILL.md" >/dev/null 2>&1; then
      continue
    fi
    printf '%s\n' "$skill"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || { printf 'source inventory is empty: %s\n' "$source_id" >&2; return 1; }
}

read_roots() {
  [ -f "$source_file" ] && [ -f "$marker_file" ] || { printf 'source discovery state missing: %s\n' "$source_id" >&2; return 1; }
  source_root="$(sed -n '1p' "$source_file")"
  marker_root="$(sed -n '1p' "$marker_file")"
}

case "$action" in
  discover)
    discover_source
    ;;
  inspect)
    read_roots
    emit_copy_inspection "$plan_path" "$source_root" "$marker_root" "$repo_root/skills" claude "$owner" "$repo_root"
    emit_copy_inspection "$plan_path" "$source_root" "$marker_root" "$home/.agents/skills" codex "$owner" "$repo_root"
    ;;
  reconcile)
    read_roots
    failed=0
    reconcile_copy_actions "$plan_path" "$source_root" "$marker_root" \
      "$repo_root/skills" claude "$owner" "$repo_root" || failed=1
    reconcile_copy_actions "$plan_path" "$source_root" "$marker_root" \
      "$home/.agents/skills" codex "$owner" "$repo_root" || failed=1
    refresh_copy_gitignore "$repo_root" "$repo_root/skills" "$owner" || failed=1
    exit "$failed"
    ;;
  verify)
    read_roots
    failed=0
    verify_copy_states "$plan_path" "$source_root" "$marker_root" "$repo_root/skills" claude "$owner" "$repo_root" || failed=1
    verify_copy_states "$plan_path" "$source_root" "$marker_root" "$home/.agents/skills" codex "$owner" "$repo_root" || failed=1
    exit "$failed"
    ;;
  *)
    printf 'unknown copy-source adapter action: %s\n' "$action" >&2
    exit 1
    ;;
esac
