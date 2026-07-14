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
canonical_root="$home/.agents/skills"
claude_root="$repo_root/skills"
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

inspect_canonical() { # skill current lock inventory
  local skill="$1"
  local current_lock="$2"
  local lock_source upstream_path destination="$canonical_root/$skill"
  lock_source="$(lock_source_for "$current_lock" "$skill")"
  if [ -z "$lock_source" ]; then
    [ -e "$destination" ] && printf 'foreign\tunowned\n' || printf 'absent\tmissing\n'
    return
  fi
  if [ "$lock_source" != "$upstream_repo" ] && ! { [ "$skill" = find-skills ] && [ "$lock_source" = "$retired_repo" ]; }; then
    printf 'foreign\tother-source\n'
    return
  fi
  if [ ! -f "$destination/SKILL.md" ]; then
    printf 'drift\tmissing-copy\n'
    return
  fi
  if [ "$lock_source" = "$upstream_repo" ] && upstream_path="$(upstream_path_for "$skill" 2>/dev/null)"; then
    if ! diff -qr -x .agent-scripts-copy "$upstream_path" "$destination" >/dev/null 2>&1; then
      printf 'drift\tcontent-mismatch\n'
      return
    fi
  fi
  printf 'present\tmanaged\n'
}

emit_inspection() {
  local current_lock="$state_root/current-lock.tsv"
  local expected skill destination state detail upstream_path marker marker_owner orphan lock_skill lock_source
  read_lock_inventory "$current_lock"

  while IFS=$'\t' read -r expected skill destination; do
    if [ "$destination" = codex ]; then
      IFS=$'\t' read -r state detail < <(inspect_canonical "$skill" "$current_lock")
    else
      upstream_path="$(upstream_path_for "$skill")"
      IFS=$'\t' read -r state detail < <(
        inspect_copy_state "$upstream_path" "$canonical_root/$skill" \
          "$claude_root/$skill" "$owner" "$repo_root"
      )
    fi
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

  if [ -d "$claude_root" ]; then
    for marker in "$claude_root"/*/.agent-scripts-copy; do
      [ -f "$marker" ] || continue
      marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
      orphan="$(basename "$(dirname "$marker")")"
      if [ "$marker_owner" = "$owner" ]; then
        if ! awk -F '\t' -v skill="$orphan" '$2 == skill && $3 == "claude" { found = 1 } END { exit !found }' "$plan_path"; then
          printf 'orphan\t%s\tclaude\tmanaged\n' "$orphan"
        fi
      elif [ "$orphan" = find-skills ] && [ "$marker_owner" = "$retired_owner" ]; then
        printf 'orphan\tfind-skills\tclaude\tmanaged\n'
      fi
    done
  fi
}

run_skills() {
  local output rc=0
  output="$(npx --yes skills@latest "$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] || printf '%s' "$output" | grep -q 'Failed to '; then
    [ -n "$output" ] && printf '%s\n' "$output" >&2
    return 1
  fi
}

validate_complete_canonical() {
  local current_lock="$state_root/installed-lock.tsv"
  local skill relative lock_source
  read_lock_inventory "$current_lock"
  while IFS=$'\t' read -r skill relative; do
    lock_source="$(lock_source_for "$current_lock" "$skill")"
    if [ "$lock_source" != "$upstream_repo" ] \
      || [ ! -f "$canonical_root/$skill/SKILL.md" ] \
      || ! diff -qr -x .agent-scripts-copy "$(sed -n '1p' "$upstream_root_file")/$relative" \
        "$canonical_root/$skill" >/dev/null 2>&1; then
      printf 'incomplete Matt installed inventory: %s\n' "$skill" >&2
      return 1
    fi
  done < "$inventory_file"
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

refresh_owner_ignore() { # owner ignore file
  local copy_owner="$1"
  local ignore_file="$2"
  local marker marker_owner name entries=()
  mkdir -p "$(dirname "$ignore_file")"
  if [ -d "$claude_root" ]; then
    for marker in "$claude_root"/*/.agent-scripts-copy; do
      [ -f "$marker" ] || continue
      marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
      [ "$marker_owner" = "$copy_owner" ] || continue
      name="$(basename "$(dirname "$marker")")"
      entries+=("skills/$name")
    done
  fi
  touch "$ignore_file"
  if [ "${#entries[@]}" -eq 0 ]; then
    remove_gitignore_block "$ignore_file" "$copy_owner"
    return
  fi
  regen_gitignore_block "$ignore_file" "$copy_owner" update-skill-topology.sh \
    ${entries[@]+"${entries[@]}"}
}

reconcile_states() {
  local current_lock="$state_root/pre-reconcile-lock.tsv"
  local operation skill destination lock_source failed=0 needs_add=0
  local matt_removals=() retired_removals=()
  local claude_plan="$state_root/claude-plan.tsv"
  local retired_claude_plan="$state_root/retired-claude-plan.tsv"

  read_lock_inventory "$current_lock"
  if ! cmp -s "$lock_snapshot" "$current_lock"; then
    printf 'skills lock changed after Matt preflight\n' >&2
    return 1
  fi
  : > "$claude_plan"
  : > "$retired_claude_plan"
  while IFS=$'\t' read -r operation skill destination; do
    if [ "$destination" = codex ]; then
      if [ "$operation" = install ]; then
        needs_add=1
      elif [ "$operation" = remove ]; then
        lock_source="$(lock_source_for "$current_lock" "$skill")"
        if [ "$lock_source" = "$upstream_repo" ]; then
          matt_removals+=("$skill")
        elif [ "$skill" = find-skills ] && [ "$lock_source" = "$retired_repo" ]; then
          retired_removals+=("$skill")
        else
          printf 'refusing unsafe npx removal: %s\n' "$skill" >&2
          return 1
        fi
      fi
    elif [ "$skill" = find-skills ]; then
      printf '%s\t%s\t%s\n' "$operation" "$skill" "$destination" >> "$retired_claude_plan"
    else
      printf '%s\t%s\t%s\n' "$operation" "$skill" "$destination" >> "$claude_plan"
    fi
  done < "$plan_path"

  if [ "$needs_add" -eq 1 ]; then
    if ! run_skills add mattpocock/skills --skill '*' --agent codex --global --yes; then
      printf 'Matt skills install failed\n' >&2
      return 1
    fi
  fi
  validate_complete_canonical || return 1

  if [ "${#matt_removals[@]}" -gt 0 ] || [ "${#retired_removals[@]}" -gt 0 ]; then
    if ! run_skills remove "${matt_removals[@]}" "${retired_removals[@]}" --global --agent codex --yes; then
      printf 'Matt skills removal failed\n' >&2
      return 1
    fi
    remove_lock_entries "${matt_removals[@]}" "${retired_removals[@]}"
    for skill in "${matt_removals[@]}" "${retired_removals[@]}"; do
      [ -n "$skill" ] || continue
      rm -rf -- "$canonical_root/$skill"
    done
  fi

  while IFS=$'\t' read -r operation skill destination; do
    [ "$destination" = codex ] || continue
    [ "$operation" = install ] && printf 'installed\t%s\tcodex\n' "$skill"
    [ "$operation" = remove ] && printf 'removed\t%s\tcodex\n' "$skill"
  done < "$plan_path"

  reconcile_copy_actions "$claude_plan" "$canonical_root" "$canonical_root" \
    "$claude_root" claude "$owner" "$repo_root" || failed=1
  reconcile_copy_actions "$retired_claude_plan" "$canonical_root" "$canonical_root" \
    "$claude_root" claude "$retired_owner" "$repo_root" || failed=1
  refresh_owner_ignore "$owner" "$repo_root/.git/info/exclude" || failed=1
  refresh_owner_ignore "$retired_owner" "$repo_root/.gitignore" || failed=1
  return "$failed"
}

verify_states() {
  local current_lock="$state_root/verify-lock.tsv"
  local expected skill destination state detail failed=0 upstream_path
  read_lock_inventory "$current_lock"
  while IFS=$'\t' read -r expected skill destination; do
    if [ "$destination" = codex ]; then
      IFS=$'\t' read -r state detail < <(inspect_canonical "$skill" "$current_lock")
    else
      if upstream_path="$(upstream_path_for "$skill" 2>/dev/null)"; then
        IFS=$'\t' read -r state detail < <(
          inspect_copy_state "$upstream_path" "$canonical_root/$skill" \
            "$claude_root/$skill" "$owner" "$repo_root"
        )
      elif [ "$skill" = find-skills ]; then
        if [ ! -e "$claude_root/$skill" ]; then state=absent; detail=missing
        elif [ "$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)" = "$retired_owner" ]; then state=present; detail=managed
        else state=foreign; detail=unowned
        fi
      else
        if [ ! -e "$claude_root/$skill" ]; then state=absent; detail=missing
        elif [ "$(sed -n '2p' "$claude_root/$skill/.agent-scripts-copy" 2>/dev/null || true)" = "$owner" ]; then state=present; detail=managed
        else state=foreign; detail=unowned
        fi
      fi
    fi
    case "$expected:$state" in
      present:present|absent:absent|absent:foreign) ;;
      *) printf 'npx skill verification failed: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2; failed=1 ;;
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
