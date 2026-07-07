#!/usr/bin/env bash
set -euo pipefail

# Update all Claude Code marketplaces and plugins/skills

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $*"; }
section() { echo -e "\n${YELLOW}>>> $*${NC}"; }

PLUGINS_JSON="${HOME}/.claude/plugins/installed_plugins.json"

# 1. Update all marketplaces
section "Updating marketplaces"
claude plugin marketplace update
info "All marketplaces updated"

# 2. Update all installed plugins
section "Updating plugins"
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse $PLUGINS_JSON" >&2
  exit 1
fi
if [ ! -f "$PLUGINS_JSON" ]; then
  echo "plugins file missing: $PLUGINS_JSON" >&2
  exit 1
fi

plugin_list="$(jq -r '.plugins // {} | keys[]' "$PLUGINS_JSON")"
plugin_keys=()
if [ -n "$plugin_list" ]; then
  while IFS= read -r plugin_key; do
    # Windows jq emits CRLF; a trailing \r makes `claude plugin update`
    # report the plugin as not found in the marketplace.
    plugin_keys+=("$(printf '%s' "$plugin_key" | tr -d '\r')")
  done <<< "$plugin_list"
fi

ok=0
not_found=()
failed=()
for plugin_key in "${plugin_keys[@]}"; do
  printf '  Updating %s... ' "$plugin_key"
  if output="$(claude plugin update "$plugin_key" 2>&1)"; then
    printf 'ok\n'
    ok=$((ok + 1))
  else
    msg="${output//$'\r'/}"
    if printf '%s' "$msg" | grep -qi 'not found'; then
      printf 'skipped (not found in marketplace)\n'
      not_found+=("$plugin_key")
    else
      printf 'FAILED (%s)\n' "$msg"
      failed+=("$plugin_key"$'\t'"$msg")
    fi
  fi
done

printf '\nResults: %d updated, %d skipped, %d failed\n' "$ok" "${#not_found[@]}" "${#failed[@]}"
if [ "${#not_found[@]}" -gt 0 ]; then
  printf 'Skipped (no longer in marketplace — consider uninstalling):\n'
  for plugin_key in "${not_found[@]}"; do
    printf '  - %s\n' "$plugin_key"
  done
fi
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'Failed:\n'
  for entry in "${failed[@]}"; do
    printf '  - %s: %s\n' "${entry%%$'\t'*}" "${entry#*$'\t'}"
  done
  exit 1
fi

section "Done — restart Claude Code to apply updates"
