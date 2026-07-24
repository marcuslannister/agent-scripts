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
source "${BASH_SOURCE[0]%/*}/../claude-root.sh"

case "$source_id" in
  anthropic-skills)
    repo_url="https://github.com/anthropics/skills.git"
    clone_name="anthropic-skills"
    source_suffix="skills"
    owner="anthropic-skills"
    staging_owner="anthropics"
    staging_tracking=ignored
    ;;
  khazix-skills)
    repo_url="https://github.com/KKKKhazix/khazix-skills.git"
    clone_name="khazix-skills"
    source_suffix=""
    owner="khazix-skills"
    staging_owner="marcus"
    staging_tracking=tracked
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

surface_for_destination() {
  case "$1" in
    claude) claude_root_surface_path "$home" "$discovery_root" ;;
    codex) printf '%s/.agents/skills\n' "$home" ;;
  esac
}

tracked_stage_skill() { # skill
  [ "$staging_tracking" = tracked ] \
    && git -C "$repo_root" ls-files --error-unmatch \
      "other-skills/$staging_owner/$1/SKILL.md" >/dev/null 2>&1
}

inspect_stage_state() { # skill
  local skill="$1"
  if [ -f "$staging_root/$skill/SKILL.md" ] \
    && [ ! -f "$staging_root/$skill/.agent-scripts-copy" ] && tracked_stage_skill "$skill"; then
    printf 'drift\ttracked-update\n'
  else
    inspect_copy_state "$source_root/$skill" "$marker_root/$skill" \
      "$staging_root/$skill" "$owner" "$repo_root"
  fi
}

install_staged_skill() { # skill
  local skill="$1"
  if [ ! -f "$staging_root/$skill/.agent-scripts-copy" ] && tracked_stage_skill "$skill"; then
    mkdir -p "$staging_root/$skill"
    printf '%s\n%s\n' "$marker_root/$skill" "$owner" > "$staging_root/$skill/.agent-scripts-copy"
  fi
  install_skill_copy "$source_root/$skill" "$staging_root/$skill" "$owner" >/dev/null
}

inspect_staging_state() { # expected skill destination
  local _expected="$1" skill="$2" destination="$3" surface
  if [ "$destination" = staging ]; then
    inspect_stage_state "$skill"
    return
  fi
  surface="$(surface_for_destination "$destination")"
  inspect_copy_state "$staging_root/$skill" "$staging_root/$skill" \
    "$surface/$skill" "$owner" "$repo_root"
}

emit_staging_inspection() {
  local expected skill destination state detail
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination")
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"

  local surface marker marker_owner orphan
  for destination in claude codex; do
    surface="$(surface_for_destination "$destination")"
    [ -d "$surface" ] || continue
    for marker in "$surface"/*/.agent-scripts-copy; do
      [ -f "$marker" ] || continue
      marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
      [ "$marker_owner" = "$owner" ] || continue
      orphan="$(basename "$(dirname "$marker")")"
      if ! awk -F '\t' -v skill="$orphan" -v destination="$destination" \
        '$2 == skill && $3 == destination { found = 1 } END { exit !found }' "$plan_path"; then
        printf 'orphan\t%s\t%s\tmanaged\n' "$orphan" "$destination"
      fi
    done
  done

  local skill_file
  for skill_file in "$staging_root"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    orphan="$(basename "$(dirname "$skill_file")")"
    marker_owner="$(sed -n '2p' "$staging_root/$orphan/.agent-scripts-copy" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || tracked_stage_skill "$orphan" || continue
    rg -Fxq -- "$orphan" "$discovery_root/$source_id.inventory" && continue
    printf 'orphan\t%s\tstaging\tmanaged\n' "$orphan"
  done
}

remove_owned_legacy_copy() { # skill destination
  local skill="$1" destination="$2" surface marker_owner
  surface="$(surface_for_destination "$destination")"
  marker_owner="$(sed -n '2p' "$surface/$skill/.agent-scripts-copy" 2>/dev/null || true)"
  [ "$marker_owner" = "$owner" ] || return 0
  rm -rf -- "${surface:?}/$skill"
}

refresh_installed_surface_copies() { # skill
  local skill="$1" destination surface failed=0
  for destination in claude codex; do
    surface="$(surface_for_destination "$destination")"
    refresh_owned_staged_surface_copy "$plan_path" "$staging_root" "$skill" \
      "$surface" "$destination" "$owner" || failed=1
  done
  return "$failed"
}

refresh_staging_ignore() {
  local marker marker_owner name entries=()
  mkdir -p "$staging_root"
  for marker in "$staging_root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || continue
    name="$(basename "$(dirname "$marker")")"
    if [ "$staging_tracking" = tracked ]; then
      entries+=("other-skills/$staging_owner/$name/.agent-scripts-copy")
    else
      entries+=("other-skills/$staging_owner/$name")
    fi
  done
  regen_gitignore_block "$repo_root/.gitignore" "$owner" update-skill-topology.sh \
    ${entries[@]+"${entries[@]}"}
}

reconcile_staging() {
  local operation skill destination state detail marker_owner surface failed=0 operation_failed
  while IFS=$'\t' read -r operation skill destination; do
    operation_failed=0
    case "$operation:$destination" in
      install:staging)
        IFS=$'\t' read -r state detail < <(inspect_stage_state "$skill")
        ensure_staged_skill "$skill" || operation_failed=1
        if [ "$operation_failed" -eq 0 ] && [ "$state" = drift ]; then
          refresh_installed_surface_copies "$skill" || operation_failed=1
        fi
        ;;
      install:claude|install:codex)
        surface="$(surface_for_destination "$destination")"
        if ! ensure_staged_skill "$skill"; then
          operation_failed=1
        elif ! install_staged_surface_copy "$staging_root" "$skill" "$surface" \
          "$destination" "$owner" "$repo_root"; then
          operation_failed=1
        fi
        ;;
      remove:staging)
        marker_owner="$(sed -n '2p' "$staging_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ "$marker_owner" = "$owner" ] || tracked_stage_skill "$skill"; then
          rm -rf -- "${staging_root:?}/$skill" || operation_failed=1
        fi
        ;;
      remove:claude|remove:codex)
        remove_owned_legacy_copy "$skill" "$destination" || operation_failed=1
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
  refresh_staging_ignore || failed=1
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
