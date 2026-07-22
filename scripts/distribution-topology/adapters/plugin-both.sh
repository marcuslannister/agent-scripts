#!/usr/bin/env bash
set -uo pipefail

source_id="${1:?source ID required}"
repo_root="${2:?repo root required}"
discovery_root="${3:?discovery root required}"
action="${4:-discover}"
plan_path="${5:-}"
home="${6:?home required}"
mode="${7:-reconcile}"

registry="$repo_root/scripts/distribution-topology/registry.json"
plugin_name="$(jq -er --arg source_id "$source_id" '.[] | select(.sourceId == $source_id) | .plugin.name' "$registry")"
plugin_repo="$(jq -er --arg source_id "$source_id" '.[] | select(.sourceId == $source_id) | .plugin.repo' "$registry")"
remote_root="$discovery_root/$source_id/repo"

discover_remote_marketplace() {
  mkdir -p "$(dirname "$remote_root")"
  git clone --depth 1 --quiet "https://github.com/$plugin_repo.git" "$remote_root"
}

marketplace_for() {
  jq -er --arg source_id "$source_id" --arg destination "$1" \
    '.[] | select(.sourceId == $source_id) | .plugin.marketplaces[$destination]' "$registry"
}

if [ "$source_id" = claude-mem ]; then
  source "${BASH_SOURCE[0]%/*}/claude-mem-dependencies.sh"
fi

require_source_dependencies() {
  [ "$source_id" != claude-mem ] || require_claude_mem_dependencies
}

PLUGIN_INVENTORY_JSON=
PLUGIN_INVENTORY_ERROR=

load_plugin_inventory() {
  local destination="$1"
  local output
  PLUGIN_INVENTORY_JSON=
  PLUGIN_INVENTORY_ERROR=

  case "$destination" in
    claude)
      if ! output="$(claude plugin list --json 2>&1)"; then
        PLUGIN_INVENTORY_ERROR="Claude plugin inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$output"; then
        PLUGIN_INVENTORY_ERROR="Claude plugin inventory returned invalid JSON"
        return 1
      fi
      PLUGIN_INVENTORY_JSON="$(jq -c '
        map({
          id: .id,
          version: (.version // ""),
          enabled: (.enabled // false),
          system: (.id | endswith("@claude-plugins-official"))
        })
      ' <<< "$output")"
      ;;
    codex)
      if ! output="$(codex plugin list --json 2>&1)"; then
        PLUGIN_INVENTORY_ERROR="Codex plugin inventory failed: ${output//$'\n'/ }"
        return 1
      fi
      if ! jq -e '(.installed // []) | type == "array"' >/dev/null 2>&1 <<< "$output"; then
        PLUGIN_INVENTORY_ERROR="Codex plugin inventory returned invalid JSON"
        return 1
      fi
      PLUGIN_INVENTORY_JSON="$(jq -c '
        (.installed // [])
        | map(
            select(.installed == true)
            | {
                id: .pluginId,
                version: (.version // ""),
                enabled: (.enabled // false),
                system: (
                  (.marketplaceName // "") == "openai-primary-runtime"
                  or (.marketplaceName // "") == "openai-bundled"
                )
              }
          )
      ' <<< "$output")"
      ;;
    *)
      PLUGIN_INVENTORY_ERROR="unknown plugin destination: $destination"
      return 1
      ;;
  esac
}

PLUGIN_STATE=
PLUGIN_VERSION=
PLUGIN_ERROR=

load_plugin_state() {
  local destination="$1"
  local marketplace plugin_id record
  marketplace="$(marketplace_for "$destination")"
  plugin_id="$plugin_name@$marketplace"
  PLUGIN_STATE=
  PLUGIN_VERSION=
  PLUGIN_ERROR=

  if ! load_plugin_inventory "$destination"; then
    PLUGIN_ERROR="$PLUGIN_INVENTORY_ERROR"
    return 1
  fi

  record="$(jq -c --arg id "$plugin_id" 'first(.[]? | select(.id == $id)) // empty' <<< "$PLUGIN_INVENTORY_JSON")"
  if [ -z "$record" ]; then
    PLUGIN_STATE=missing
    return 0
  fi
  PLUGIN_VERSION="$(jq -r '.version' <<< "$record")"
  if [ "$(jq -r '.enabled' <<< "$record")" = true ]; then
    PLUGIN_STATE=enabled
  else
    PLUGIN_STATE=disabled
  fi
}

PLUGIN_AVAILABLE_VERSION=
PLUGIN_FRESHNESS_ERROR=

load_claude_available_plugin_version() {
  local marketplace plugin_id manifest version source_path plugin_root plugin_manifest
  marketplace="$(marketplace_for claude)"
  plugin_id="$plugin_name@$marketplace"
  manifest="$remote_root/.claude-plugin/marketplace.json"
  PLUGIN_AVAILABLE_VERSION=
  PLUGIN_FRESHNESS_ERROR=

  if [ ! -r "$manifest" ]; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Claude plugin version for $plugin_id: remote marketplace manifest is unreadable"
    return 1
  fi
  if version="$(jq -er --arg plugin "$plugin_name" '
    .plugins | select(type == "array") |
    [.[] | select(.name == $plugin)] | select(length == 1) |
    .[0].version | select(type == "string" and length > 0)
  ' "$manifest" 2>/dev/null)"; then
    PLUGIN_AVAILABLE_VERSION="$version"
    return 0
  fi
  if source_path="$(jq -er --arg plugin "$plugin_name" '
    .plugins | select(type == "array") |
    [.[] | select(.name == $plugin)] | select(length == 1) |
    .[0].source | select(type == "string" and length > 0)
  ' "$manifest" 2>/dev/null)"; then
    case "$source_path" in
      /*) plugin_root="$source_path" ;;
      *) plugin_root="$remote_root/${source_path#./}" ;;
    esac
    plugin_root="${plugin_root%/}"
    plugin_manifest="$plugin_root/.claude-plugin/plugin.json"
    if [ -r "$plugin_manifest" ] && version="$(jq -er --arg plugin "$plugin_name" '
      select(.name == $plugin) | .version | select(type == "string" and length > 0)
    ' "$plugin_manifest" 2>/dev/null)"; then
      PLUGIN_AVAILABLE_VERSION="$version"
      return 0
    fi
  fi
  PLUGIN_FRESHNESS_ERROR="cannot determine available Claude plugin version for $plugin_id: remote marketplace manifest has no unique version"
  return 1
}

load_codex_available_plugin_version() {
  local marketplace plugin_id marketplace_manifest count source_kind source_path
  local plugin_root manifest version
  marketplace="$(marketplace_for codex)"
  plugin_id="$plugin_name@$marketplace"
  marketplace_manifest="$remote_root/.agents/plugins/marketplace.json"
  PLUGIN_AVAILABLE_VERSION=
  PLUGIN_FRESHNESS_ERROR=

  if [ ! -r "$marketplace_manifest" ]; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: remote marketplace manifest is unreadable"
    return 1
  fi
  count="$(jq -r --arg plugin "$plugin_name" '[.plugins[]? | select(.name == $plugin)] | length' "$marketplace_manifest" 2>/dev/null || printf 0)"
  if [ "$count" -ne 1 ]; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: remote marketplace manifest has no unique plugin"
    return 1
  fi
  source_kind="$(jq -r --arg plugin "$plugin_name" 'first(.plugins[] | select(.name == $plugin)).source.source // ""' "$marketplace_manifest")"
  if [ "$source_kind" != local ]; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: unsupported marketplace source $source_kind"
    return 1
  fi
  if ! source_path="$(jq -er --arg plugin "$plugin_name" '
    first(.plugins[] | select(.name == $plugin)).source.path | select(type == "string" and length > 0)
  ' "$marketplace_manifest" 2>/dev/null)"; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: marketplace source path is missing"
    return 1
  fi
  case "$source_path" in
    /*) plugin_root="$source_path" ;;
    *) plugin_root="$remote_root/${source_path#./}" ;;
  esac
  manifest="$plugin_root/.codex-plugin/plugin.json"
  if [ ! -r "$manifest" ]; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: remote plugin manifest is unreadable"
    return 1
  fi
  if ! version="$(jq -er --arg plugin "$plugin_name" '
    select(.name == $plugin) | .version | select(type == "string" and length > 0)
  ' "$manifest" 2>/dev/null)"; then
    PLUGIN_FRESHNESS_ERROR="cannot determine available Codex plugin version for $plugin_id: remote plugin manifest has no version"
    return 1
  fi
  PLUGIN_AVAILABLE_VERSION="$version"
}

load_plugin_available_version() {
  case "$1" in
    claude) load_claude_available_plugin_version ;;
    codex) load_codex_available_plugin_version ;;
    *)
      PLUGIN_FRESHNESS_ERROR="cannot determine available plugin version for unknown destination: $1"
      return 1
      ;;
  esac
}

PLUGIN_FRESHNESS_STATE=
PLUGIN_FRESHNESS_DETAIL=

evaluate_plugin_freshness() {
  local destination="$1"
  PLUGIN_FRESHNESS_STATE=
  PLUGIN_FRESHNESS_DETAIL=
  if ! load_plugin_available_version "$destination"; then
    if [ "$mode" = reconcile ] && [ "$PLUGIN_STATE" = missing ]; then
      PLUGIN_FRESHNESS_STATE=not-installed
      return 0
    fi
    PLUGIN_FRESHNESS_STATE=error
    PLUGIN_FRESHNESS_DETAIL="$PLUGIN_FRESHNESS_ERROR"
    return 1
  fi
  if [ "$PLUGIN_STATE" = missing ]; then
    PLUGIN_FRESHNESS_STATE=not-installed
  elif [ -z "$PLUGIN_VERSION" ]; then
    PLUGIN_FRESHNESS_STATE=error
    PLUGIN_FRESHNESS_DETAIL="cannot determine installed plugin version"
    return 1
  elif [ "$PLUGIN_VERSION" = "$PLUGIN_AVAILABLE_VERSION" ]; then
    PLUGIN_FRESHNESS_STATE=current
  else
    PLUGIN_FRESHNESS_STATE=outdated
    PLUGIN_FRESHNESS_DETAIL="installed $PLUGIN_VERSION, available $PLUGIN_AVAILABLE_VERSION"
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
  local destination plugin_id failed=0
  [ -e "$marker" ] && return 0
  if [ ! -f "$discovery_root/native-plugins.tsv" ]; then
    printf 'native plugin allowlist is missing\n' >&2
    return 1
  fi

  for destination in claude codex; do
    if ! load_plugin_inventory "$destination"; then
      printf '%s while checking manifest scope\n' "$PLUGIN_INVENTORY_ERROR" >&2
      failed=1
      continue
    fi
    while IFS= read -r plugin_id; do
      [ -n "$plugin_id" ] || continue
      plugin_is_allowed "$destination" "$plugin_id" ||
        emit_unknown_plugin "$destination" "$plugin_id" || failed=1
    done < <(jq -r '.[] | select(.system == false) | .id // empty' <<< "$PLUGIN_INVENTORY_JSON")
  done

  [ "$failed" -eq 0 ] && : > "$marker"
  return "$failed"
}

inspect_states() {
  local expected skill destination state detail failed=0
  while IFS=$'\t' read -r expected skill destination; do
    [ -n "$expected" ] || continue
    if ! load_plugin_state "$destination"; then
      state=error
      detail="$PLUGIN_ERROR"
      failed=1
    elif ! evaluate_plugin_freshness "$destination"; then
      state=error
      detail="$PLUGIN_FRESHNESS_DETAIL"
      failed=1
    else
      case "$PLUGIN_STATE" in
        enabled)
          if [ "$expected" != present ]; then
            state=present
            detail=managed
          elif [ "$PLUGIN_FRESHNESS_STATE" = current ]; then
            state=present
            detail=managed
          else
            state=outdated
            detail="$PLUGIN_FRESHNESS_DETAIL"
          fi
          ;;
        disabled)
          if [ "$expected" != present ]; then
            state=present
            detail=managed-disabled
          elif [ "$PLUGIN_FRESHNESS_STATE" = current ]; then
            state=present
            detail=managed-disabled
          else
            state=outdated
            detail="$PLUGIN_FRESHNESS_DETAIL"
          fi
          ;;
        missing) state=absent; detail=missing ;;
      esac
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
      ensure_marketplace "$destination" || return 1
      case "$destination:$before_state" in
        claude:missing)
          run_native "Claude plugin install failed for $plugin_id" \
            claude plugin install "$plugin_id" || return 1
          ;;
        claude:disabled)
          run_native "Claude plugin update failed for $plugin_id" \
            claude plugin update "$plugin_id" || return 1
          if load_plugin_state claude && [ "$PLUGIN_STATE" = enabled ]; then
            run_native "Claude plugin disable failed for $plugin_id" \
              claude plugin disable "$plugin_id" || return 1
          fi
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
          run_native "Codex plugin update failed for $plugin_id" \
            codex plugin add "$plugin_id" || return 1
          ;;
        codex:disabled)
          run_native "Codex plugin update failed for $plugin_id" \
            codex plugin add "$plugin_id" || return 1
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
  if [ "$PLUGIN_STATE" != "$before_state" ] && [ "$before_state" != missing ]; then
    printf '%s plugin %s changed state from %s to %s after %s\n' \
      "$destination" "$plugin_id" "$before_state" "$PLUGIN_STATE" "$operation" >&2
    return 1
  fi
  if [ "$before_state" = missing ] && [ "$PLUGIN_STATE" != enabled ]; then
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
    if ! evaluate_plugin_freshness "$destination"; then
      printf 'plugin verification failed: %s/%s -> %s: %s\n' \
        "$source_id" "$skill" "$destination" "$PLUGIN_FRESHNESS_DETAIL" >&2
      failed=1
      continue
    fi
    case "$expected:$PLUGIN_STATE:$PLUGIN_FRESHNESS_STATE" in
      present:enabled:current|present:disabled:current|absent:missing:not-installed) ;;
      present:enabled:outdated|present:disabled:outdated)
        printf 'plugin verification failed: %s/%s -> %s: %s\n' \
          "$source_id" "$skill" "$destination" "$PLUGIN_FRESHNESS_DETAIL" >&2
        failed=1
        ;;
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
    discover_remote_marketplace || exit 1
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
