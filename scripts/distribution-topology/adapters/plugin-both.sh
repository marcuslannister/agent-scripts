#!/usr/bin/env bash
set -uo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"

registry="$repo_root/scripts/distribution-topology/registry.json"
plugin_name="$(jq -er --arg source_id "$source_id" '.[] | select(.sourceId == $source_id) | .plugin.name' "$registry")"
plugin_repo="$(jq -er --arg source_id "$source_id" '.[] | select(.sourceId == $source_id) | .plugin.repo' "$registry")"

marketplace_for() {
  jq -er --arg source_id "$source_id" --arg destination "$1" \
    '.[] | select(.sourceId == $source_id) | .plugin.marketplaces[$destination]' "$registry"
}

find_claude_mem_bun() {
  local candidate found
  for candidate in \
    "$home"/scoop/apps/bun/*/bun.exe \
    "$home/scoop/apps/bun/current/bun.exe" \
    "$home/scoop/shims/bun" \
    "$home/scoop/shims/bun.exe" \
    "$home/.bun/bin/bun" \
    "$home/.bun/bin/bun.exe" \
    /usr/local/bin/bun \
    /opt/homebrew/bin/bun \
    /home/linuxbrew/.linuxbrew/bin/bun
  do
    [ -e "$candidate" ] || continue
    "$candidate" --version >/dev/null 2>&1 && return 0
  done
  found="$(command -v bun 2>/dev/null || true)"
  [ -n "$found" ] && "$found" --version >/dev/null 2>&1
}

find_claude_mem_uv_command() {
  local command_name="$1"
  local candidate found
  for candidate in \
    "$home"/scoop/apps/uv/*/"${command_name}.exe" \
    "$home/scoop/apps/uv/current/${command_name}.exe" \
    "$home/scoop/shims/${command_name}" \
    "$home/scoop/shims/${command_name}.exe" \
    "$home/.local/bin/${command_name}" \
    /usr/local/bin/"$command_name" \
    /opt/homebrew/bin/"$command_name" \
    /home/linuxbrew/.linuxbrew/bin/"$command_name"
  do
    [ -e "$candidate" ] || continue
    "$candidate" --version >/dev/null 2>&1 && return 0
  done
  found="$(command -v "$command_name" 2>/dev/null || true)"
  [ -n "$found" ] && "$found" --version >/dev/null 2>&1
}

require_source_dependencies() {
  [ "$source_id" = claude-mem ] || return 0
  local failed=0
  if ! find_claude_mem_bun; then
    printf 'claude-mem requires runnable Bun for its shared hooks; install or repair Bun: https://bun.sh/docs/installation\n' >&2
    failed=1
  fi
  if ! find_claude_mem_uv_command uv || ! find_claude_mem_uv_command uvx; then
    printf 'claude-mem requires runnable uv and uvx for shared vector search; install or repair Astral uv\n' >&2
    failed=1
  fi
  return "$failed"
}

PLUGIN_STATE=
PLUGIN_VERSION=
PLUGIN_ERROR=

load_plugin_state() {
  local destination="$1"
  local marketplace plugin_id output record
  marketplace="$(marketplace_for "$destination")"
  plugin_id="$plugin_name@$marketplace"
  PLUGIN_STATE=
  PLUGIN_VERSION=
  PLUGIN_ERROR=

  case "$destination" in
    claude)
      if ! output="$(claude plugin list --json 2>&1)"; then
        PLUGIN_ERROR="Claude plugin inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$output"; then
        PLUGIN_ERROR="Claude plugin inventory returned invalid JSON"
        return 1
      fi
      record="$(jq -c --arg id "$plugin_id" 'first(.[]? | select(.id == $id)) // empty' <<< "$output")"
      ;;
    codex)
      if ! output="$(codex plugin list --json 2>&1)"; then
        PLUGIN_ERROR="Codex plugin inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e '(.installed // []) | type == "array"' >/dev/null 2>&1 <<< "$output"; then
        PLUGIN_ERROR="Codex plugin inventory returned invalid JSON"
        return 1
      fi
      record="$(jq -c --arg id "$plugin_id" 'first(.installed[]? | select(.pluginId == $id and .installed == true)) // empty' <<< "$output")"
      ;;
    *)
      PLUGIN_ERROR="unknown plugin destination: $destination"
      return 1
      ;;
  esac

  if [ -z "$record" ]; then
    PLUGIN_STATE=missing
    return 0
  fi
  PLUGIN_VERSION="$(jq -r '.version // ""' <<< "$record")"
  if [ "$(jq -r '.enabled // false' <<< "$record")" = true ]; then
    PLUGIN_STATE=enabled
  else
    PLUGIN_STATE=disabled
  fi
}

MARKETPLACE_STATE=
MARKETPLACE_ERROR=

load_marketplace_state() {
  local destination="$1"
  local marketplace output
  marketplace="$(marketplace_for "$destination")"
  MARKETPLACE_STATE=
  MARKETPLACE_ERROR=

  case "$destination" in
    claude)
      if ! output="$(claude plugin marketplace list --json 2>&1)"; then
        MARKETPLACE_ERROR="Claude marketplace inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$output"; then
        MARKETPLACE_ERROR="Claude marketplace inventory returned invalid JSON"
        return 1
      fi
      if jq -e --arg marketplace "$marketplace" 'any(.[]?; .name == $marketplace)' >/dev/null <<< "$output"; then
        MARKETPLACE_STATE=present
      else
        MARKETPLACE_STATE=missing
      fi
      ;;
    codex)
      if ! output="$(codex plugin marketplace list --json 2>&1)"; then
        MARKETPLACE_ERROR="Codex marketplace inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e '(.marketplaces // []) | type == "array"' >/dev/null 2>&1 <<< "$output"; then
        MARKETPLACE_ERROR="Codex marketplace inventory returned invalid JSON"
        return 1
      fi
      if jq -e --arg marketplace "$marketplace" 'any(.marketplaces[]?; .name == $marketplace)' >/dev/null <<< "$output"; then
        MARKETPLACE_STATE=present
      else
        MARKETPLACE_STATE=missing
      fi
      ;;
  esac
}

NATIVE_OUTPUT=

run_native() {
  local label="$1"
  shift
  if NATIVE_OUTPUT="$("$@" 2>&1)"; then
    return 0
  fi
  printf '%s: %s\n' "$label" "${NATIVE_OUTPUT//$'\n'/ }" >&2
  return 1
}

upgrade_codex_marketplace() {
  local marketplace="$1"
  local attempt
  for attempt in 1 2 3; do
    run_native "Codex marketplace upgrade failed for $marketplace" \
      codex plugin marketplace upgrade "$marketplace" && return 0
    [ "$attempt" -lt 3 ] || return 1
    sleep "${PLUGIN_RETRY_DELAY_SECONDS:-2}"
  done
}

ensure_marketplace() {
  local destination="$1"
  local marketplace
  marketplace="$(marketplace_for "$destination")"
  if ! load_marketplace_state "$destination"; then
    printf '%s\n' "$MARKETPLACE_ERROR" >&2
    return 1
  fi

  case "$destination:$MARKETPLACE_STATE" in
    claude:missing)
      run_native "Claude marketplace add failed for $marketplace" \
        claude plugin marketplace add "$plugin_repo"
      ;;
    claude:present)
      run_native "Claude marketplace update failed for $marketplace" \
        claude plugin marketplace update "$marketplace"
      ;;
    codex:missing)
      run_native "Codex marketplace add failed for $marketplace" \
        codex plugin marketplace add "$plugin_repo"
      ;;
    codex:present)
      upgrade_codex_marketplace "$marketplace"
      ;;
  esac
}


plugin_is_allowed() {
  local destination="$1"
  local plugin_id="$2"
  awk -F '\t' -v destination="$destination" -v plugin_id="$plugin_id" \
    '$1 == destination && $2 == plugin_id { found = 1 } END { exit !found }' \
    "$discovery_root/native-plugins.tsv"
}

emit_unknown_plugin() {
  local destination="$1"
  local plugin_id="$2"
  local name="${plugin_id%@*}"
  case "$name" in
    ''|*[!a-z0-9-]*)
      printf 'invalid installed plugin id from %s: %s\n' "$destination" "$plugin_id" >&2
      return 1
      ;;
  esac
  printf 'decision\t%s\t%s\t%s\n' "$name" "$destination" "$plugin_id"
}

scan_unknown_plugins() {
  local marker="$discovery_root/native-plugin-inventory-scanned"
  local output plugin_id failed=0
  [ -e "$marker" ] && return 0
  if [ ! -f "$discovery_root/native-plugins.tsv" ]; then
    printf 'native plugin allowlist is missing\n' >&2
    return 1
  fi

  if ! output="$(claude plugin list --json 2>&1)"; then
    printf 'Claude plugin inventory failed while checking manifest scope: %s\n' "${output//$'\n'/ }" >&2
    failed=1
  elif ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$output"; then
    printf 'Claude plugin inventory returned invalid JSON while checking manifest scope\n' >&2
    failed=1
  else
    while IFS= read -r plugin_id; do
      [ -n "$plugin_id" ] || continue
      case "$plugin_id" in
        *@claude-plugins-official) continue ;;
      esac
      plugin_is_allowed claude "$plugin_id" || emit_unknown_plugin claude "$plugin_id" || failed=1
    done < <(jq -r '.[].id // empty' <<< "$output")
  fi

  if ! output="$(codex plugin list --json 2>&1)"; then
    printf 'Codex plugin inventory failed while checking manifest scope: %s\n' "${output//$'\n'/ }" >&2
    failed=1
  elif ! jq -e '(.installed // []) | type == "array"' >/dev/null 2>&1 <<< "$output"; then
    printf 'Codex plugin inventory returned invalid JSON while checking manifest scope\n' >&2
    failed=1
  else
    while IFS= read -r plugin_id; do
      [ -n "$plugin_id" ] || continue
      plugin_is_allowed codex "$plugin_id" || emit_unknown_plugin codex "$plugin_id" || failed=1
    done < <(jq -r '
      .installed[]?
      | select(.installed == true)
      | select((.marketplaceName // "" | startswith("openai-")) | not)
      | .pluginId // empty
    ' <<< "$output")
  fi

  [ "$failed" -eq 0 ] && : > "$marker"
  return "$failed"
}


inspect_states() {
  local expected skill destination state detail failed=0
  while IFS=$'\t' read -r expected skill destination; do
    [ -n "$expected" ] || continue
    if load_plugin_state "$destination"; then
      case "$PLUGIN_STATE" in
        enabled) state=present; detail=managed ;;
        disabled) state=drift; detail=disabled ;;
        missing) state=absent; detail=missing ;;
      esac
    else
      state=error
      detail="$PLUGIN_ERROR"
      failed=1
    fi
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"
  return "$failed"
}

apply_destination() {
  local operation="$1"
  local skill="$2"
  local destination="$3"
  local marketplace plugin_id before_state before_version
  marketplace="$(marketplace_for "$destination")"
  plugin_id="$plugin_name@$marketplace"

  if ! load_plugin_state "$destination"; then
    printf '%s\n' "$PLUGIN_ERROR" >&2
    return 1
  fi
  before_state="$PLUGIN_STATE"
  before_version="$PLUGIN_VERSION"

  case "$operation" in
    remove)
      [ "$before_state" != missing ] || return 0
      case "$destination" in
        claude)
          run_native "Claude plugin removal failed for $plugin_id" \
            claude plugin uninstall "$plugin_id" || return 1
          ;;
        codex)
          run_native "Codex plugin removal failed for $plugin_id" \
            codex plugin remove "$plugin_id" || return 1
          ;;
      esac
      printf 'removed\t%s\t%s\n' "$skill" "$destination"
      return 0
      ;;
    install|refresh)
      if [ "$destination" = codex ] && [ "$before_state" = disabled ]; then
        printf 'Codex plugin %s is installed but disabled; re-enable it in Codex config before retrying\n' "$plugin_id" >&2
        return 1
      fi
      ensure_marketplace "$destination" || return 1
      case "$destination:$before_state" in
        claude:missing)
          run_native "Claude plugin install failed for $plugin_id" \
            claude plugin install "$plugin_id" || return 1
          ;;
        claude:disabled)
          run_native "Claude plugin enable failed for $plugin_id" \
            claude plugin enable "$plugin_id" || return 1
          run_native "Claude plugin update failed for $plugin_id" \
            claude plugin update "$plugin_id" || return 1
          ;;
        claude:enabled)
          run_native "Claude plugin update failed for $plugin_id" \
            claude plugin update "$plugin_id" || return 1
          ;;
        codex:missing)
          run_native "Codex plugin install failed for $plugin_id" \
            codex plugin add "$plugin_id" || return 1
          ;;
        codex:enabled)
          ;;
      esac
      ;;
    *)
      printf 'unknown plugin operation: %s\n' "$operation" >&2
      return 1
      ;;
  esac

  if ! load_plugin_state "$destination"; then
    printf '%s\n' "$PLUGIN_ERROR" >&2
    return 1
  fi
  if [ "$PLUGIN_STATE" != enabled ]; then
    printf '%s plugin %s remains %s after %s\n' "$destination" "$plugin_id" "$PLUGIN_STATE" "$operation" >&2
    return 1
  fi

  if [ "$operation" = install ]; then
    printf 'installed\t%s\t%s\n' "$skill" "$destination"
  elif [ "$before_version" != "$PLUGIN_VERSION" ]; then
    printf 'updated\t%s\t%s\n' "$skill" "$destination"
  fi
}

reconcile_states() {
  local operation skill destination failed=0
  while IFS=$'\t' read -r operation skill destination; do
    [ -n "$operation" ] || continue
    apply_destination "$operation" "$skill" "$destination" || failed=1
  done < "$plan_path"
  return "$failed"
}

verify_states() {
  local expected skill destination failed=0
  while IFS=$'\t' read -r expected skill destination; do
    [ -n "$expected" ] || continue
    if ! load_plugin_state "$destination"; then
      printf 'plugin verification failed: %s/%s -> %s: %s\n' "$source_id" "$skill" "$destination" "$PLUGIN_ERROR" >&2
      failed=1
      continue
    fi
    case "$expected:$PLUGIN_STATE" in
      present:enabled|absent:missing) ;;
      *)
        printf 'plugin verification failed: %s/%s -> %s: expected %s, found %s\n' \
          "$source_id" "$skill" "$destination" "$expected" "$PLUGIN_STATE" >&2
        failed=1
        ;;
    esac
  done < "$plan_path"
  return "$failed"
}

case "$action" in
  discover)
    require_source_dependencies || exit 1
    printf '%s\n' "$plugin_name"
    ;;
  inspect)
    failed=0
    scan_unknown_plugins || failed=1
    inspect_states || failed=1
    exit "$failed"
    ;;
  reconcile)
    reconcile_states
    ;;
  verify)
    verify_states
    ;;
  *)
    printf 'unknown plugin adapter action: %s\n' "$action" >&2
    exit 1
    ;;
esac
