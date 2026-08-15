#!/usr/bin/env bash
set -uo pipefail

# Operator-run repair for a desynced Codex plugin registry.
#
# Codex can lose its marketplace and installed-plugin records while the snapshots
# stay on disk. `plugin marketplace list` then reports nothing while `plugin
# marketplace add` refuses with "already added from a different source" — for
# claude-mem re-adding means a full 330MB clone that cannot finish. Observed
# after a Codex CLI reinstall.
#
# Reports by default. --fix re-registers each expected marketplace and plugin
# through `codex` commands only, never by writing Codex internal state
# (ADR-0007). It is deliberately not wired into update-all.sh or update-local.sh:
# native-state repair stays an explicit operator action.

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
SOURCES="$SCRIPT_DIR/sources.json"

info() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2; }

usage() {
  printf '%s\n' \
    'Usage: repair-codex-registry.sh [--fix]' \
    '' \
    'Report the Codex marketplaces and plugins this repo expects, and whether' \
    'Codex still records them.' \
    '' \
    'Options:' \
    '  --fix      Re-register every entry Codex has lost: marketplace remove,' \
    '             marketplace add, then plugin add.' \
    '  -h, --help Show this help and exit.'
}

fix=0
for argument in "$@"; do
  case "$argument" in
    -h|--help) usage; exit 0 ;;
    --fix) fix=1 ;;
    *)
      warn "unknown option: $argument"
      printf 'Run repair-codex-registry.sh --help for usage.\n' >&2
      exit 2
      ;;
  esac
done

for tool in codex jq; do
  command -v "$tool" >/dev/null 2>&1 && continue
  warn "required tool not found: $tool"
  exit 2
done
[ -f "$SOURCES" ] || { warn "missing sources list: $SOURCES"; exit 2; }

# Every source that expects a native Codex plugin, as one TSV row per source.
expected_rows() {
  jq -r '
    .sources[]
    | select(.plugin.marketplaces.codex != null)
    | [ .id,
        .repo,
        .plugin.marketplaces.codex,
        (.plugin.name + "@" + .plugin.marketplaces.codex)
      ] | @tsv
  ' "$SOURCES"
}

marketplace_present() { # marketplace
  codex plugin marketplace list --json 2>/dev/null \
    | jq -e --arg name "$1" 'any((.marketplaces // [])[]; .name == $name)' >/dev/null
}

plugin_installed() { # plugin_id
  codex plugin list --json 2>/dev/null \
    | jq -e --arg id "$1" 'any((.installed // [])[]; .pluginId == $id and .installed == true)' >/dev/null
}

repair_source() { # source_id repo marketplace plugin_id market_state
  local source_id="$1" repo="$2" marketplace="$3" plugin_id="$4" market_state="$5"
  # A registered marketplace is left alone: re-adding it throws away a snapshot
  # that Codex rebuilds with a full clone, which for claude-mem is half an hour.
  if [ "$market_state" != present ]; then
    # Remove first: a lost registry entry leaves a stale root behind that makes a
    # plain add refuse. Removing an entry Codex no longer lists is not an error.
    codex plugin marketplace remove "$marketplace" >/dev/null 2>&1
    if ! codex plugin marketplace add "$repo"; then
      warn "$source_id: could not add marketplace $marketplace from $repo"
      return 1
    fi
    if ! marketplace_present "$marketplace"; then
      warn "$source_id: marketplace $marketplace is still missing after add"
      return 1
    fi
  fi
  if ! codex plugin add "$plugin_id"; then
    warn "$source_id: could not install plugin $plugin_id"
    return 1
  fi
  plugin_installed "$plugin_id" && return 0
  warn "$source_id: plugin $plugin_id is still missing after install"
  return 1
}

desynced=0
failed=0
while IFS=$'\t' read -r source_id repo marketplace plugin_id; do
  [ -n "$source_id" ] || continue
  market_state=missing
  plugin_state=missing
  marketplace_present "$marketplace" && market_state=present
  plugin_installed "$plugin_id" && plugin_state=installed
  if [ "$market_state" = present ] && [ "$plugin_state" = installed ]; then
    printf '\033[0;32m✓\033[0m %-14s marketplace %-20s plugin %s\n' \
      "$source_id" "$marketplace" "$plugin_id"
    continue
  fi
  desynced=$((desynced + 1))
  printf '\033[0;31m✗\033[0m %-14s marketplace %-20s %s; plugin %s %s\n' \
    "$source_id" "$marketplace" "$market_state" "$plugin_id" "$plugin_state"
  [ "$fix" -eq 1 ] || continue
  info "repairing $source_id"
  repair_source "$source_id" "$repo" "$marketplace" "$plugin_id" "$market_state" \
    || failed=$((failed + 1))
done < <(expected_rows)

if [ "$desynced" -eq 0 ]; then
  info "Codex registry matches every expected marketplace and plugin"
  exit 0
fi
entries=entries
[ "$desynced" -eq 1 ] && entries=entry
if [ "$fix" -eq 0 ]; then
  warn "$desynced Codex $entries desynced; rerun with --fix to re-register"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  warn "$failed of $desynced repairs failed"
  exit 1
fi
info "repaired $desynced Codex $entries"
exit 0
