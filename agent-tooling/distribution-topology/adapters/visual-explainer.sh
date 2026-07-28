#!/usr/bin/env bash
set -euo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"
mode="${7:-reconcile}"

[ "$source_id" = visual-explainer ] || { printf 'unknown visual source: %s\n' "$source_id" >&2; exit 1; }
source "$repo_root/agent-tooling/lib-copies.sh"
source "${BASH_SOURCE[0]%/*}/copy-state.sh"

repo_url="https://github.com/nicobailon/visual-explainer.git"
owner="visual-explainer"
staging_owner="nicobailon"
plugin_id="visual-explainer@visual-explainer-marketplace"
marketplace="visual-explainer-marketplace"
source_file="$discovery_root/$source_id.source-root"
commit_file="$discovery_root/$source_id.commit"
staging_root="$repo_root/other-skills/$staging_owner"

discover_source() {
  local clone_dir source_root commit
  if [ "$mode" = check ]; then
    clone_dir="$discovery_root/$source_id/repo"
  else
    clone_dir="$home/Projects/visual-explainer"
  fi
  refresh_source_clone "$clone_dir" "$repo_url"
  source_root="$clone_dir/plugins"
  [ -f "$source_root/visual-explainer/SKILL.md" ] \
    || { printf 'visual-explainer inventory is incomplete\n' >&2; return 1; }
  commit="$(git -C "$clone_dir" rev-parse HEAD)"
  [ -n "$commit" ] && [[ "$commit" != *$'\t'* ]] \
    || { printf 'visual-explainer source commit is invalid\n' >&2; return 1; }
  printf '%s\n' "$source_root" > "$source_file"
  printf '%s\n' "$commit" > "$commit_file"
  printf 'visual-explainer\n'
}

read_source_state() {
  [ -f "$source_file" ] && [ -f "$commit_file" ] \
    || { printf 'visual-explainer discovery state missing\n' >&2; return 1; }
  source_root="$(sed -n '1p' "$source_file")"
  source_commit="$(sed -n '1p' "$commit_file")"
}

inspect_claude_plugin() {
  local installed_file="$home/.claude/plugins/installed_plugins.json"
  local settings_file="$home/.claude/settings.json"
  local installed_count installed_commit enabled
  if [ ! -f "$installed_file" ]; then
    printf 'absent\tmissing\n'
    return
  fi
  if ! installed_count="$(jq -er --arg id "$plugin_id" '(.plugins[$id] // []) | length' "$installed_file" 2>/dev/null)"; then
    printf 'error\tinvalid-plugin-state\n'
    return
  fi
  if [ "$installed_count" -eq 0 ]; then
    printf 'absent\tmissing\n'
    return
  fi
  if [ ! -f "$settings_file" ]; then
    printf 'error\tplugin-settings-missing\n'
    return
  fi
  if ! jq -e --arg id "$plugin_id" '
    type == "object" and
    ((has("enabledPlugins") | not) or
      ((.enabledPlugins | type) == "object" and
        ((.enabledPlugins | has($id) | not) or
          (.enabledPlugins[$id] | type) == "boolean")))
  ' "$settings_file" >/dev/null 2>&1; then
    printf 'error\tinvalid-plugin-settings\n'
    return
  fi
  enabled="$(jq -r --arg id "$plugin_id" '.enabledPlugins[$id] // false' "$settings_file")"
  installed_commit="$(jq -r --arg id "$plugin_id" '(.plugins[$id] // [] | last | .gitCommitSha) // empty' "$installed_file" 2>/dev/null || true)"
  if [ -z "$installed_commit" ]; then
    printf 'drift\tunstamped\n'
  elif [ "$installed_commit" != "$source_commit" ]; then
    printf 'drift\tcontent-mismatch\n'
  elif [ "$enabled" = true ]; then
    printf 'present\tmanaged\n'
  else
    printf 'present\tmanaged-disabled\n'
  fi
}

inspect_stage_state() { # skill
  inspect_stage_tree "$source_root/$1" "$staging_root/$1"
}

install_staged_skill() { # skill
  install_stage_tree "$source_root/$1" "$staging_root/$1" >/dev/null
}

inspect_destination_state() { # skill destination
  local skill="$1"
  local destination="$2"
  local state detail
  case "$destination" in
    staging)
      inspect_stage_state "$skill"
      ;;
    claude)
      inspect_claude_plugin
      ;;
    *) printf 'error\tinvalid-destination\n' ;;
  esac
}

inspect_states() {
  local expected skill destination state detail orphan skill_file
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_destination_state "$skill" "$destination")
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"

  for skill_file in "$staging_root"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    orphan="$(basename "$(dirname "$skill_file")")"
    rg -Fxq -- "$orphan" "$discovery_root/$source_id.inventory" && continue
    printf 'orphan\t%s\tstaging\tmanaged\n' "$orphan"
  done
}

plugin_is_installed() {
  local installed_file="$home/.claude/plugins/installed_plugins.json"
  [ -f "$installed_file" ] \
    && jq -e --arg id "$plugin_id" '((.plugins[$id] // []) | length) > 0' "$installed_file" >/dev/null 2>&1
}

plugin_is_enabled() {
  local settings_file="$home/.claude/settings.json"
  [ -f "$settings_file" ] \
    && jq -e --arg id "$plugin_id" '.enabledPlugins[$id] == true' "$settings_file" >/dev/null 2>&1
}

run_native() {
  local label="$1" output
  shift
  if output="$("$@" 2>&1)"; then
    return 0
  fi
  printf '%s: %s\n' "$label" "${output//$'\n'/ }" >&2
  return 1
}

reconcile_claude_plugin() { # install|remove
  local operation="$1"
  local marketplace_output was_enabled=true was_installed=false
  if plugin_is_installed; then
    was_installed=true
    plugin_is_enabled || was_enabled=false
  fi
  case "$operation" in
    install)
      if ! marketplace_output="$(claude plugin marketplace list 2>&1)"; then
        printf 'failed to inspect Claude marketplaces: %s\n' "$marketplace_output" >&2
        return 1
      fi
      if printf '%s\n' "$marketplace_output" \
        | grep -qE "(^|[^[:alnum:]_.-])${marketplace}([^[:alnum:]_.-]|$)"; then
        run_native "failed to update Claude marketplace $marketplace" \
          claude plugin marketplace update "$marketplace" || return 1
      else
        run_native 'failed to add visual-explainer Claude marketplace' \
          claude plugin marketplace add nicobailon/visual-explainer || return 1
      fi
      if [ "$was_installed" = true ]; then
        run_native "failed to update Claude plugin $plugin_id" \
          claude plugin update "$plugin_id" || return 1
        if [ "$was_enabled" = false ] && plugin_is_enabled; then
          run_native "failed to restore disabled Claude plugin $plugin_id" \
            claude plugin disable "$plugin_id" || return 1
        fi
        printf 'updated\tvisual-explainer\tclaude\n'
      else
        run_native "failed to install Claude plugin $plugin_id" \
          claude plugin install "$plugin_id" || return 1
        printf 'installed\tvisual-explainer\tclaude\n'
      fi
      ;;
    remove)
      if plugin_is_installed; then
        run_native "failed to uninstall Claude plugin $plugin_id" \
          claude plugin uninstall "$plugin_id" || return 1
        printf 'removed\tvisual-explainer\tclaude\n'
      fi
      ;;
    *) printf 'unknown visual plugin operation: %s\n' "$operation" >&2; return 1 ;;
  esac
}

refresh_staging_metadata() {
  local skill_file clone_dir
  mkdir -p "$staging_root"
  for skill_file in "$staging_root"/*/.agent-scripts-copy "$staging_root"/*/.agent-scripts-copy-source; do
    [ -e "$skill_file" ] || continue
    rm -f "$skill_file"
  done
  clear_staging_gitignore "$repo_root" "$owner" || return 1
  clear_staging_gitignore "$repo_root" "$staging_owner" || return 1
  clone_dir="$source_root"
  [ -d "$clone_dir/.git" ] || clone_dir="$(dirname "$source_root")"
  write_staging_source_json "$staging_root" "$repo_url" "$clone_dir"
}

reconcile_states() {
  local operation skill destination
  local failed=0 operation_failed
  while IFS=$'\t' read -r operation skill destination; do
    operation_failed=0
    case "$operation:$destination" in
      install:staging)
        ensure_staged_skill "$skill" || operation_failed=1
        ;;
      install:claude)
        reconcile_claude_plugin install || operation_failed=1
        if [ "$operation_failed" -eq 0 ]; then
          continue
        fi
        ;;
      remove:staging)
        if [ -e "$staging_root/$skill" ]; then
          rm -rf -- "${staging_root:?}/$skill" || operation_failed=1
        fi
        ;;
      remove:claude)
        reconcile_claude_plugin remove || operation_failed=1
        if [ "$operation_failed" -eq 0 ]; then
          continue
        fi
        ;;
      *)
        printf 'unknown visual operation: %s %s\n' "$operation" "$destination" >&2
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
  local expected skill destination state detail failed=0
  while IFS=$'\t' read -r expected skill destination; do
    IFS=$'\t' read -r state detail < <(inspect_destination_state "$skill" "$destination")
    case "$expected:$state" in
      present:present|absent:absent|absent:foreign) ;;
      *) printf 'visual-explainer verification failed: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2; failed=1 ;;
    esac
  done < "$plan_path"
  return "$failed"
}

case "$action" in
  discover) discover_source ;;
  inspect) read_source_state; inspect_states ;;
  reconcile) read_source_state; reconcile_states ;;
  verify) read_source_state; verify_states ;;
  *) printf 'unknown visual adapter action: %s\n' "$action" >&2; exit 1 ;;
esac
