#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"

case "$source_id" in
  matt-skills)
    upstream_repo="mattpocock/skills"
    retired_repo="vercel-labs/skills"
    owner="matt-skills"
    retired_owner="cli-skills"
    repo_subroot="skills"
    staging_dir="matt"
    ;;
  humanlayer-skills)
    upstream_repo="humanlayer/skills"
    retired_repo=""
    owner="humanlayer-skills"
    retired_owner=""
    repo_subroot="plugins/improve-claude-md/skills"
    staging_dir="humanlayer"
    ;;
  *)
    printf 'unknown npx source: %s\n' "$source_id" >&2
    exit 1
    ;;
esac

# All npx repos any registered source in this adapter owns, across every
# source_id — used so one source's lock scan doesn't flag another
# registered source's entries as unknown.
known_npx_repos=("mattpocock/skills" "humanlayer/skills" "vercel-labs/skills")

is_known_npx_repo() {
  local repo="$1" candidate
  for candidate in "${known_npx_repos[@]}"; do
    [ "$candidate" = "$repo" ] && return 0
  done
  return 1
}

source "$repo_root/agent-tooling/lib-copies.sh"
source "${BASH_SOURCE[0]%/*}/copy-state.sh"
source "${BASH_SOURCE[0]%/*}/../claude-root.sh"

lock="$home/.agents/.skill-lock.json"
codex_root="$home/.agents/skills"
claude_root="$(claude_root_surface_path "$home" "$discovery_root")"
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
  upstream_root="$clone_root"
  [ -z "$repo_subroot" ] || upstream_root="$clone_root/$repo_subroot"
  [ -d "$upstream_root" ] || { printf '%s upstream skills root missing\n' "$upstream_repo" >&2; return 1; }
  printf '%s\n' "$upstream_root" > "$upstream_root_file"
  : > "$inventory_file"
  while IFS= read -r skill_file; do
    skill="$(basename "$(dirname "$skill_file")")"
    valid_skill_name "$skill" || { printf 'invalid %s upstream skill: %s\n' "$upstream_repo" "$skill" >&2; return 1; }
    relative="${skill_file#"$upstream_root/"}"
    relative="${relative%/SKILL.md}"
    printf '%s\t%s\n' "$skill" "$relative" >> "$inventory_file"
    count=$((count + 1))
  done < <(find "$upstream_root" -name SKILL.md -type f | LC_ALL=C sort)
  [ "$count" -gt 0 ] || { printf '%s upstream inventory is empty\n' "$upstream_repo" >&2; return 1; }
  if cut -f1 "$inventory_file" | LC_ALL=C sort | uniq -d | grep -q .; then
    printf '%s upstream inventory contains duplicate skill names\n' "$upstream_repo" >&2
    return 1
  fi
  LC_ALL=C sort -u "$inventory_file" -o "$inventory_file"
  read_lock_inventory "$lock_snapshot"
  cut -f1 "$inventory_file"
}

staging_root="$repo_root/other-skills/$staging_dir"

marker_path_for() { # skill
  local relative
  relative="$(awk -F '\t' -v skill="$1" '$1 == skill { print $2; exit }' "$inventory_file")"
  [ -n "$relative" ] || return 1
  printf '%s/Projects/%s/%s\n' "$home" "$owner" "$relative"
}

inspect_staging_state() { # expected skill destination current-lock
  local _expected="$1" skill="$2" destination="$3" current_lock="$4"
  local upstream_path marker_path lock_source marker_owner
  case "$destination" in
    staging)
      if ! upstream_path="$(upstream_path_for "$skill" 2>/dev/null)"; then
        if [ ! -e "$staging_root/$skill" ]; then
          printf 'absent\tremoved\n'
        else
          printf 'present\tmanaged\n'
        fi
        return
      fi
      inspect_stage_tree "$upstream_path" "$staging_root/$skill"
      ;;
    codex)
      lock_source="$(lock_source_for "$current_lock" "$skill")"
      if [ -n "$lock_source" ] && {
        [ "$lock_source" = "$upstream_repo" ] \
          || { [ -n "$retired_repo" ] && [ "$lock_source" = "$retired_repo" ]; }
      }; then
        printf 'legacy-npx-lock\t%s\n' "$lock_source"
      elif [ -n "$lock_source" ]; then
        printf 'foreign\t%s\n' "$lock_source"
      else
        inspect_copy_state "$staging_root/$skill" "$staging_root/$skill" \
          "$codex_root/$skill" "$owner" "$repo_root"
      fi
      ;;
    claude)
      marker_owner="$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
      if [ "$marker_owner" = "$owner" ] || { [ -n "$retired_owner" ] && [ "$marker_owner" = "$retired_owner" ]; }; then
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
  local expected skill destination state detail lock_skill lock_source marker marker_owner orphan skill_file
  read_lock_inventory "$current_lock"
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_staging_state "$expected" "$skill" "$destination" "$current_lock")
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"
  while IFS=$'\t' read -r lock_skill lock_source; do
    if [ "$lock_source" = "$upstream_repo" ] \
      || { [ -n "$retired_repo" ] && [ "$lock_source" = "$retired_repo" ]; }; then
      # Plan-row skills already emit legacy-npx-lock from inspect_staging_state.
      if awk -F '\t' -v skill="$lock_skill" '$2 == skill && $3 == "codex" { found = 1 } END { exit !found }' "$plan_path"; then
        continue
      fi
      printf 'legacy-npx-lock\t%s\tcodex\t%s\n' "$lock_skill" "$lock_source"
    elif is_known_npx_repo "$lock_source"; then
      : # owned by a sibling registered npx source; that source's own scan covers it
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
    [ "$marker_owner" = "$owner" ] || { [ -n "$retired_owner" ] && [ "$marker_owner" = "$retired_owner" ]; } || continue
    orphan="$(basename "$(dirname "$marker")")"
    if ! awk -F '\t' -v skill="$orphan" '$2 == skill && $3 == "claude" { found = 1 } END { exit !found }' "$plan_path"; then
      printf 'orphan\t%s\tclaude\tmanaged\n' "$orphan"
    fi
  done
  for skill_file in "$staging_root"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    orphan="$(basename "$(dirname "$skill_file")")"
    awk -F '\t' -v skill="$orphan" '$1 == skill { found = 1 } END { exit !found }' "$inventory_file" && continue
    printf 'orphan\t%s\tstaging\tmanaged\n' "$orphan"
  done
}

inspect_stage_state() { # skill
  inspect_staging_state present "$1" staging "$lock_snapshot"
}

install_staged_skill() { # skill
  local skill="$1" upstream_path
  upstream_path="$(upstream_path_for "$skill")"
  install_stage_tree "$upstream_path" "$staging_root/$skill" >/dev/null
}

refresh_installed_codex_copy() { # skill
  refresh_owned_staged_surface_copy "$plan_path" "$staging_root" "$1" \
    "$codex_root" codex "$owner"
}

refresh_staging_metadata() {
  local skill_file clone_dir
  mkdir -p "$staging_root"
  for skill_file in "$staging_root"/*/.agent-scripts-copy "$staging_root"/*/.agent-scripts-copy-source; do
    [ -e "$skill_file" ] || continue
    rm -f "$skill_file"
  done
  clear_staging_gitignore "$repo_root" "$owner" || return 1
  [ -z "$retired_owner" ] || clear_staging_gitignore "$repo_root" "$retired_owner" || return 1
  if [ -f "$repo_root/.git/info/exclude" ]; then
    remove_gitignore_block "$repo_root/.git/info/exclude" "$owner" || return 1
  fi
  clone_dir="$state_root/repo"
  write_staging_source_json "$staging_root" "$upstream_repo" "$clone_dir"
}

reconcile_states() {
  local current_lock="$state_root/pre-reconcile-lock.tsv"
  local operation skill destination state detail marker_owner
  local failed=0 operation_failed
  read_lock_inventory "$current_lock"
  if ! cmp -s "$lock_snapshot" "$current_lock"; then
    printf 'skills lock changed after Matt preflight\n' >&2
    return 1
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
        if [ -e "$staging_root/$skill" ]; then
          rm -rf -- "${staging_root:?}/$skill" || operation_failed=1
        fi
        ;;
      remove:claude)
        marker_owner="$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)"
        if [ "$marker_owner" = "$owner" ] || { [ -n "$retired_owner" ] && [ "$marker_owner" = "$retired_owner" ]; }; then
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
  refresh_staging_metadata || failed=1
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
