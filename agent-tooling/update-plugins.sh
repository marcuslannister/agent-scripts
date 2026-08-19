#!/usr/bin/env bash
set -uo pipefail

# Best-effort native plugin refresh (ADR-0009). Runs the native update commands
# for every plugin source in sources.json, honors manual-upgrade markers, and
# never fails the run: a broken update is one warning line, not a stopped
# updater. Installs and registry repair stay operator actions
# (repair-codex-registry.sh for a desynced Codex registry).

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
SOURCES_PATH="$SCRIPT_DIR/sources.json"

info() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2; }

if [ ! -f "$SOURCES_PATH" ] || ! command -v jq >/dev/null 2>&1; then
  warn "cannot refresh plugins: missing sources.json or jq"
  exit 0
fi

run_native() { # label command...
  local label="$1" output
  shift
  if output="$("$@" 2>&1)"; then
    return 0
  fi
  warn "$label: ${output//$'\n'/ }"
  return 1
}

CLAUDE_INSTALLED=
CODEX_INSTALLED=

plugin_installed() { # installed_list plugin_id
  [ -n "$1" ] && printf '%s\n' "$1" | rg -Fxq -- "$2"
}

# An unreadable inventory is reported, never treated as "nothing installed":
# that would silently skip every plugin update behind a "not installed" line.
claude_inventory_ok=0
if command -v claude >/dev/null 2>&1; then
  if ! claude_inventory="$(claude plugin list --json 2>&1)"; then
    warn "Claude plugin inventory failed; skipping Claude plugin refresh: ${claude_inventory//$'\n'/ }"
  elif ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$claude_inventory"; then
    warn "Claude plugin inventory returned invalid JSON; skipping Claude plugin refresh"
  else
    claude_inventory_ok=1
    CLAUDE_INSTALLED="$(jq -r '.[].id' <<< "$claude_inventory")"
  fi
else
  info "claude CLI not found; skipping Claude plugin refresh"
fi

if [ "$claude_inventory_ok" -eq 1 ]; then
  while IFS=$'\t' read -r source_id plugin_name marketplace; do
    [ -n "$source_id" ] || continue
    plugin_id="$plugin_name@$marketplace"
    run_native "$source_id: Claude marketplace update failed" \
      claude plugin marketplace update "$marketplace" || continue
    if plugin_installed "$CLAUDE_INSTALLED" "$plugin_id"; then
      run_native "$source_id: Claude plugin update failed" \
        claude plugin update "$plugin_id" \
        && info "$source_id: Claude plugin $plugin_id refreshed"
    else
      info "$source_id: Claude plugin $plugin_id not installed; skipping (install once with: claude plugin install $plugin_id)"
    fi
  done < <(jq -r '.sources[] | select(.plugin.marketplaces.claude != null) |
    [.id, .plugin.name, .plugin.marketplaces.claude] | @tsv' "$SOURCES_PATH")
fi

codex_inventory_ok=0
if command -v codex >/dev/null 2>&1; then
  if ! codex_inventory="$(codex plugin list --json 2>&1)"; then
    warn "Codex plugin inventory failed; skipping Codex plugin refresh: ${codex_inventory//$'\n'/ }"
  elif ! jq -e '(.installed // []) | type == "array"' >/dev/null 2>&1 <<< "$codex_inventory"; then
    warn "Codex plugin inventory returned invalid JSON; skipping Codex plugin refresh"
  else
    codex_inventory_ok=1
    CODEX_INSTALLED="$(jq -r '(.installed // [])[] | select(.installed == true) | .pluginId' <<< "$codex_inventory")"
  fi
else
  info "codex CLI not found; skipping Codex plugin refresh"
fi

if [ "$codex_inventory_ok" -eq 1 ]; then
  while IFS=$'\t' read -r source_id plugin_name marketplace codex_upgrade; do
    [ -n "$source_id" ] || continue
    plugin_id="$plugin_name@$marketplace"
    if [ "$codex_upgrade" = manual ]; then
      info "$source_id: Codex marketplace $marketplace is manual-upgrade (ADR-0007); skipping"
      continue
    fi
    run_native "$source_id: Codex marketplace upgrade failed" \
      codex plugin marketplace upgrade "$marketplace" || continue
    if plugin_installed "$CODEX_INSTALLED" "$plugin_id"; then
      run_native "$source_id: Codex plugin refresh failed" \
        codex plugin add "$plugin_id" \
        && info "$source_id: Codex plugin $plugin_id refreshed"
    else
      info "$source_id: Codex plugin $plugin_id not installed; skipping (install once with: codex plugin add $plugin_id)"
    fi
  done < <(jq -r '.sources[] | select(.plugin.marketplaces.codex != null) |
    [.id, .plugin.name, .plugin.marketplaces.codex, (.plugin.codexUpgrade // "auto")] | @tsv' "$SOURCES_PATH")
fi

exit 0
