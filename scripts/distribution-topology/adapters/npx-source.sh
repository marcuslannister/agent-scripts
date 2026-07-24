#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"

[ "$source_id" = matt-skills ] || { printf 'unknown npx source: %s\n' "$source_id" >&2; exit 1; }

source "$repo_root/scripts/lib-copies.sh"
source "${BASH_SOURCE[0]%/*}/copy-state.sh"

upstream_repo="mattpocock/skills"
retired_repo="vercel-labs/skills"
owner="matt-skills"
retired_owner="cli-skills"
lock="$home/.agents/.skill-lock.json"
codex_root="$home/.agents/skills"
if [ "${TOPOLOGY_CLAUDE_ROOT_LEGACY:-0}" = 1 ]; then
  claude_root="$discovery_root/claude-root-after-migration"
else
  claude_root="$home/.claude/skills"
fi
state_root="$discovery_root/$source_id"
upstream_root_file="$state_root/upstream-root"
inventory_file="$state_root/inventory.tsv"
lock_snapshot="$state_root/lock.tsv"

valid_skill_name() {
  case "$1" in ''|*[!a-z0-9-]*) return 1 ;; *) return 0 ;; esac
}

read_lock_inventory() { # output path
  local output="$1"
  local tmp="$output.tmp.$$"
  local skill lock_source
  : > "$tmp"
  if [ -f "$lock" ]; then
    if ! jq -r '
        if type != "object" or ((.skills // {}) | type) != "object" then error("invalid skills lock")
        else (.skills // {} | to_entries[] |
          [.key, (if (.value | type) == "string" then .value else (.value.source // "") end)] | @tsv)
        end
      ' "$lock" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      printf 'invalid skills lock: %s\n' "$lock" >&2
      return 1
    fi
  fi
  while IFS=$'\t' read -r skill lock_source; do
    skill="${skill%$'\r'}"
    lock_source="${lock_source%$'\r'}"
    if ! valid_skill_name "$skill" || ! printf '%s\n' "$lock_source" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
      rm -f "$tmp"
      printf 'invalid skills lock entry\n' >&2
      return 1
    fi
  done < "$tmp"
  LC_ALL=C sort -u "$tmp" -o "$tmp"
  mv "$tmp" "$output"
}

lock_source_for() { # inventory skill
  awk -F '\t' -v skill="$2" '$1 == skill { print $2; exit }' "$1"
}

upstream_path_for() { # skill
  local relative
  relative="$(awk -F '\t' -v skill="$1" '$1 == skill { print $2; exit }' "$inventory_file")"
  [ -n "$relative" ] || return 1
  printf '%s/%s\n' "$(sed -n '1p' "$upstream_root_file")" "$relative"
}

discover_source() {
  local clone_root upstream_root skill_file skill relative count=0
  mkdir -p "$state_root"
  clone_root="$state_root/repo"
  git clone --depth 1 --quiet "https://github.com/$upstream_repo.git" "$clone_root"
  upstream_root="$clone_root/skills"
  [ -d "$upstream_root" ] || { printf 'Matt upstream skills root missing\n' >&2; return 1; }
  printf '%s\n' "$upstream_root" > "$upstream_root_file"
  : > "$inventory_file"
  while IFS= read -r skill_file; do
    skill="$(basename "$(dirname "$skill_file")")"
    valid_skill_name "$skill" || { printf 'invalid Matt upstream skill: %s\n' "$skill" >&2; return 1; }
    relative="${skill_file#"$upstream_root/"}"
    relative="${relative%/SKILL.md}"
    printf '%s\t%s\n' "$skill" "$relative" >> "$inventory_file"
    count=$((count + 1))
  done < <(find "$upstream_root" -name SKILL.md -type f | LC_ALL=C sort)
  [ "$count" -gt 0 ] || { printf 'Matt upstream inventory is empty\n' >&2; return 1; }
  if cut -f1 "$inventory_file" | LC_ALL=C sort | uniq -d | grep -q .; then
    printf 'Matt upstream inventory contains duplicate skill names\n' >&2
    return 1
  fi
  LC_ALL=C sort -u "$inventory_file" -o "$inventory_file"
  read_lock_inventory "$lock_snapshot"
  cut -f1 "$inventory_file"
}

staging_root="$repo_root/other-skills/matt"

marker_path_for() { # skill
  local relative
  relative="$(awk -F '\t' -v skill="$1" '$1 == skill { print $2; exit }' "$inventory_file")"
  [ -n "$relative" ] || return 1
  printf '%s/Projects/matt-skills/%s\n' "$home" "$relative"
}

inspect_staging_state() { # expected skill destination current-lock
  local _expected="$1" skill="$2" destination="$3" current_lock="$4"
  local upstream_path marker_path lock_source marker_owner
  case "$destination" in
    staging)
      if ! upstream_path="$(upstream_path_for "$skill" 2>/dev/null)"; then
        marker_owner="$(sed -n '2p' "$staging_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ ! -e "$staging_root/$skill" ]; then
          printf 'absent\tremoved\n'
        elif [ "$marker_owner" = "$owner" ]; then
          printf 'present\tmanaged\n'
        else
          printf 'foreign\tunowned\n'
        fi
        return
      fi
      marker_path="$(marker_path_for "$skill")"
      inspect_copy_state "$upstream_path" "$marker_path" "$staging_root/$skill" "$owner" "$repo_root"
      ;;
    codex)
      lock_source="$(lock_source_for "$current_lock" "$skill")"
      if [ "$lock_source" = "$upstream_repo" ] \
        || { [ "$skill" = find-skills ] && [ "$lock_source" = "$retired_repo" ]; }; then
        printf 'drift\tlegacy-npx\n'
      elif [ -n "$lock_source" ]; then
        printf 'foreign\t%s\n' "$lock_source"
      else
        inspect_copy_state "$staging_root/$skill" "$staging_root/$skill" \
          "$codex_root/$skill" "$owner" "$repo_root"
      fi
      ;;
    claude)
      marker_owner="$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
      if [ "$marker_owner" = "$owner" ] || [ "$marker_owner" = "$retired_owner" ]; then
        printf 'present\tmanaged\n'
      elif [ -e "$claude_root/$skill" ]; then
        printf 'foreign\tunowned\n'
      else
        printf 'absent\tmissing\n'
      fi
      ;;
  esac
}

emit_inspection() {
  local current_lock="$state_root/current-lock.tsv"
  local expected skill destination state detail lock_skill lock_source marker marker_owner orphan
  read_lock_inventory "$current_lock"
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination" "$current_lock")
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"
  while IFS=$'\t' read -r lock_skill lock_source; do
    if [ "$lock_source" = "$upstream_repo" ]; then
      if ! awk -F '\t' -v skill="$lock_skill" '$1 == skill { found = 1 } END { exit !found }' "$inventory_file"; then
        printf 'orphan\t%s\tcodex\tmanaged\n' "$lock_skill"
      fi
    elif [ "$lock_skill" = find-skills ] && [ "$lock_source" = "$retired_repo" ]; then
      printf 'orphan\tfind-skills\tcodex\tmanaged\n'
    else
      printf 'npx-decision\t%s\tcodex\t%s\n' "$lock_skill" "$lock_source"
    fi
  done < "$current_lock"
  for marker in "$codex_root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || continue
    orphan="$(basename "$(dirname "$marker")")"
    awk -F '\t' -v skill="$orphan" '$1 == skill { found = 1 } END { exit !found }' "$inventory_file" && continue
    printf 'orphan\t%s\tcodex\tmanaged\n' "$orphan"
  done
  for marker in "$claude_root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || [ "$marker_owner" = "$retired_owner" ] || continue
    orphan="$(basename "$(dirname "$marker")")"
    if ! awk -F '\t' -v skill="$orphan" '$2 == skill && $3 == "claude" { found = 1 } END { exit !found }' "$plan_path"; then
      printf 'orphan\t%s\tclaude\tmanaged\n' "$orphan"
    fi
  done
  for marker in "$staging_root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || continue
    orphan="$(basename "$(dirname "$marker")")"
    awk -F '\t' -v skill="$orphan" '$1 == skill { found = 1 } END { exit !found }' "$inventory_file" && continue
    printf 'orphan\t%s\tstaging\tmanaged\n' "$orphan"
  done
}

run_skills() {
  local output rc=0
  output="$(npx --yes skills@latest "$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] || printf '%s' "$output" | grep -q 'Failed to '; then
    [ -n "$output" ] && printf '%s\n' "$output" >&2
    return 1
  fi
}

remove_lock_entries() { # names...
  local name tmp
  [ "$#" -gt 0 ] || return 0
  [ -f "$lock" ] || return 0
  tmp="$lock.tmp.$$"
  cp "$lock" "$tmp"
  for name in "$@"; do
    jq --arg name "$name" 'del(.skills[$name])' "$tmp" > "$tmp.next"
    mv "$tmp.next" "$tmp"
  done
  mv "$tmp" "$lock"
}

inspect_stage_state() { # skill
  inspect_staging_state present "$1" staging "$lock_snapshot"
}

install_staged_skill() { # skill
  local skill="$1" upstream_path marker_path
  upstream_path="$(upstream_path_for "$skill")"
  marker_path="$(marker_path_for "$skill")"
  install_skill_copy "$upstream_path" "$staging_root/$skill" "$owner" "$marker_path" >/dev/null
}

refresh_installed_codex_copy() { # skill
  refresh_owned_staged_surface_copy "$plan_path" "$staging_root" "$1" \
    "$codex_root" codex "$owner"
}

refresh_staging_ignore() {
  local marker marker_owner name entries=()
  mkdir -p "$staging_root"
  for marker in "$staging_root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || continue
    name="$(basename "$(dirname "$marker")")"
    entries+=("other-skills/matt/$name")
  done
  regen_gitignore_block "$repo_root/.gitignore" "$owner" update-skill-topology.sh \
    ${entries[@]+"${entries[@]}"}
  touch "$repo_root/.git/info/exclude"
  remove_gitignore_block "$repo_root/.git/info/exclude" "$owner"
  remove_gitignore_block "$repo_root/.gitignore" "$retired_owner"
}

reconcile_states() {
  local current_lock="$state_root/pre-reconcile-lock.tsv"
  local operation skill destination lock_source state detail marker_owner
  local failed=0 operation_failed
  local matt_removals=() retired_removals=()
  read_lock_inventory "$current_lock"
  if ! cmp -s "$lock_snapshot" "$current_lock"; then
    printf 'skills lock changed after Matt preflight\n' >&2
    return 1
  fi
  while IFS=$'\t' read -r operation skill destination; do
    [ "$destination" = codex ] || continue
    case "$operation" in install|remove) ;; *) continue ;; esac
    lock_source="$(lock_source_for "$current_lock" "$skill")"
    if [ "$lock_source" = "$upstream_repo" ]; then
      matt_removals+=("$skill")
    elif [ "$skill" = find-skills ] && [ "$lock_source" = "$retired_repo" ]; then
      retired_removals+=("$skill")
    fi
  done < "$plan_path"
  if [ "${#matt_removals[@]}" -gt 0 ] || [ "${#retired_removals[@]}" -gt 0 ]; then
    if ! run_skills remove "${matt_removals[@]}" "${retired_removals[@]}" --global --agent codex --yes; then
      printf 'Matt skills removal failed\n' >&2
      return 1
    fi
    remove_lock_entries "${matt_removals[@]}" "${retired_removals[@]}"
  fi
  while IFS=$'\t' read -r operation skill destination; do
    operation_failed=0
    case "$operation:$destination" in
      install:staging)
        IFS=$'\t' read -r state detail < <(
          inspect_staging_state present "$skill" staging "$current_lock"
        )
        ensure_staged_skill "$skill" || operation_failed=1
        if [ "$operation_failed" -eq 0 ] && [ "$state" = drift ]; then
          refresh_installed_codex_copy "$skill" || operation_failed=1
        fi
        ;;
      install:codex)
        if ! ensure_staged_skill "$skill"; then
          operation_failed=1
        elif ! install_staged_surface_copy "$staging_root" "$skill" "$codex_root" \
          codex "$owner" "$repo_root"; then
          operation_failed=1
        fi
        ;;
      remove:staging)
        marker_owner="$(sed -n '2p' "$staging_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ "$marker_owner" = "$owner" ]; then
          rm -rf -- "${staging_root:?}/$skill" || operation_failed=1
        fi
        ;;
      remove:claude)
        marker_owner="$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ "$marker_owner" = "$owner" ] || [ "$marker_owner" = "$retired_owner" ]; then
          rm -rf -- "${claude_root:?}/$skill" || operation_failed=1
        fi
        ;;
      remove:codex)
        marker_owner="$(sed -n '2p' "$codex_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ "$marker_owner" = "$owner" ]; then
          rm -rf -- "${codex_root:?}/$skill" || operation_failed=1
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
  refresh_staging_ignore || failed=1
  return "$failed"
}

verify_states() {
  local current_lock="$state_root/verify-lock.tsv"
  local expected skill destination state detail failed=0
  read_lock_inventory "$current_lock"
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination" "$current_lock")
    case "$expected:$state" in
      present:present|absent:absent|absent:foreign) ;;
      *) printf 'Matt staging verification failed: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2; failed=1 ;;
    esac
  done < "$plan_path"
  return "$failed"
}

case "$action" in
  discover) discover_source ;;
  inspect) emit_inspection ;;
  reconcile) reconcile_states ;;
  verify) verify_states ;;
  *) printf 'unknown npx-source adapter action: %s\n' "$action" >&2; exit 1 ;;
esac