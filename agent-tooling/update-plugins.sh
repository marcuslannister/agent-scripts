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

claude_plugin_installed() { # plugin_id
  [ -n "$CLAUDE_INSTALLED" ] && printf '%s\n' "$CLAUDE_INSTALLED" | rg -Fxq -- "$1"
}

codex_plugin_installed() { # plugin_id
  [ -n "$CODEX_INSTALLED" ] && printf '%s\n' "$CODEX_INSTALLED" | rg -Fxq -- "$1"
}

if command -v claude >/dev/null 2>&1; then
  CLAUDE_INSTALLED="$(claude plugin list --json 2>/dev/null \
    | jq -r 'if type == "array" then .[].id else empty end' 2>/dev/null || true)"
  while IFS=$'\t' read -r source_id plugin_name marketplace; do
    [ -n "$source_id" ] || continue
    plugin_id="$plugin_name@$marketplace"
    run_native "$source_id: Claude marketplace update failed" \
      claude plugin marketplace update "$marketplace" || continue
    if claude_plugin_installed "$plugin_id"; then
      run_native "$source_id: Claude plugin update failed" \
        claude plugin update "$plugin_id" \
        && info "$source_id: Claude plugin $plugin_id refreshed"
    else
      info "$source_id: Claude plugin $plugin_id not installed; skipping (install once with: claude plugin install $plugin_id)"
    fi
  done < <(jq -r '.sources[] | select(.plugin.marketplaces.claude != null) |
    [.id, .plugin.name, .plugin.marketplaces.claude] | @tsv' "$SOURCES_PATH")
else
  info "claude CLI not found; skipping Claude plugin refresh"
fi

if command -v codex >/dev/null 2>&1; then
  CODEX_INSTALLED="$(codex plugin list --json 2>/dev/null \
    | jq -r '(.installed // [])[] | select(.installed == true) | .pluginId' 2>/dev/null || true)"
  while IFS=$'\t' read -r source_id plugin_name marketplace codex_upgrade; do
    [ -n "$source_id" ] || continue
    plugin_id="$plugin_name@$marketplace"
    if [ "$codex_upgrade" = manual ]; then
      info "$source_id: Codex marketplace $marketplace is manual-upgrade (ADR-0007); skipping"
      continue
    fi
    run_native "$source_id: Codex marketplace upgrade failed" \
      codex plugin marketplace upgrade "$marketplace" || continue
    if codex_plugin_installed "$plugin_id"; then
      run_native "$source_id: Codex plugin refresh failed" \
        codex plugin add "$plugin_id" \
        && info "$source_id: Codex plugin $plugin_id refreshed"
    else
      info "$source_id: Codex plugin $plugin_id not installed; skipping (install once with: codex plugin add $plugin_id)"
    fi
  done < <(jq -r '.sources[] | select(.plugin.marketplaces.codex != null) |
    [.id, .plugin.name, .plugin.marketplaces.codex, (.plugin.codexUpgrade // "auto")] | @tsv' "$SOURCES_PATH")
else
  info "codex CLI not found; skipping Codex plugin refresh"
fi

exit 0
