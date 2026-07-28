#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"
mode="${7:-reconcile}"

source "$repo_root/agent-tooling/lib-copies.sh"
source "${BASH_SOURCE[0]%/*}/copy-state.sh"

case "$source_id" in
  anthropic-skills)
    repo_url="https://github.com/anthropics/skills.git"
    clone_name="anthropic-skills"
    source_suffix="skills"
    owner="anthropic-skills"
    staging_owner="anthropics"
    ;;
  khazix-skills)
    repo_url="https://github.com/KKKKhazix/khazix-skills.git"
    clone_name="khazix-skills"
    source_suffix=""
    owner="khazix-skills"
    staging_owner="khazix"
    ;;
  *)
    printf 'unknown copy source: %s\n' "$source_id" >&2
    exit 1
    ;;
esac

source_file="$discovery_root/$source_id.source-root"
marker_file="$discovery_root/$source_id.marker-root"
staging_root="$repo_root/other-skills/$staging_owner"

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

inspect_stage_state() { # skill
  local skill="$1"
  inspect_stage_tree "$source_root/$skill" "$staging_root/$skill"
}

install_staged_skill() { # skill
  local skill="$1"
  install_stage_tree "$source_root/$skill" "$staging_root/$skill" >/dev/null
}

inspect_staging_state() { # expected skill destination
  local _expected="$1" skill="$2" destination="$3"
  [ "$destination" = staging ] || { printf 'invalid acquire destination: %s\n' "$destination" >&2; return 1; }
  inspect_stage_state "$skill"
}

emit_staging_inspection() {
  local expected skill destination state detail
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination")
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"

  local skill_file orphan
  for skill_file in "$staging_root"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    orphan="$(basename "$(dirname "$skill_file")")"
    rg -Fxq -- "$orphan" "$discovery_root/$source_id.inventory" && continue
    printf 'orphan\t%s\tstaging\tmanaged\n' "$orphan"
  done
}

refresh_staging_metadata() {
  local skill_file skill clone_dir
  mkdir -p "$staging_root"
  for skill_file in "$staging_root"/*/.agent-scripts-copy "$staging_root"/*/.agent-scripts-copy-source; do
    [ -e "$skill_file" ] || continue
    rm -f "$skill_file"
  done
  clear_staging_gitignore "$repo_root" "$owner" || return 1
  clone_dir="$source_root"
  [ -d "$clone_dir/.git" ] || clone_dir="$(dirname "$source_root")"
  write_staging_source_json "$staging_root" "$repo_url" "$clone_dir"
}

reconcile_staging() {
  local operation skill destination failed=0 operation_failed
  while IFS=$'\t' read -r operation skill destination; do
    operation_failed=0
    case "$operation:$destination" in
      install:staging)
        ensure_staged_skill "$skill" || operation_failed=1
        ;;
      remove:staging)
        if [ -e "$staging_root/$skill" ]; then
          rm -rf -- "${staging_root:?}/$skill" || operation_failed=1
        fi
        ;;
      *)
        printf 'unknown staging operation: %s %s\n' "$operation" "$destination" >&2
        operation_failed=1
        ;;
    esac
    if [ "$operation_failed" -eq 0 ]; then
      case "$operation" in
        install) printf 'installed\t%s\t%s\n' "$skill" "$destination" ;;
        remove) printf 'removed\t%s\t%s\n' "$skill" "$destination" ;;
      esac
    else
      failed=1
    fi
  done < "$plan_path"
  refresh_staging_metadata || failed=1
  return "$failed"
}

verify_staging() {
  local expected skill destination state detail failed=0
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination")
    case "$expected:$state" in
      present:present|absent:absent|absent:foreign) ;;
      *) printf 'staging verification failed: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2; failed=1 ;;
    esac
  done < "$plan_path"
  return "$failed"
}

case "$action" in
  discover) discover_source ;;
  inspect) read_roots; emit_staging_inspection ;;
  reconcile) read_roots; reconcile_staging ;;
  verify) read_roots; verify_staging ;;
  *) printf 'unknown copy-source adapter action: %s\n' "$action" >&2; exit 1 ;;
esac
