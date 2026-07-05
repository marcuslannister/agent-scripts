#!/usr/bin/env bash

# Shared installer for plugins that ship both Claude Code and Codex plugin
# manifests (CLAUDE.md rule 1): one call installs/updates the plugin through
# each CLI's own marketplace commands.

plugins_info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
plugins_section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
plugins_warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

codex_marketplace_upgrade() {
  local marketplace="$1"
  local attempt

  for attempt in 1 2 3; do
    if codex plugin marketplace upgrade "$marketplace"; then
      return 0
    fi
    [ "$attempt" -lt 3 ] || return 1
    plugins_warn "codex marketplace upgrade failed; retrying ($attempt/3)"
    sleep 2
  done
}

# Anchored name match: a bare `grep -q NAME` would substring-match other
# entries (e.g. a "my-NAME-fork" marketplace) and skip the add branch.
marketplace_listed() { # claude|codex marketplace_name
  "$1" plugin marketplace list 2>/dev/null \
    | grep -qE "(^|[^[:alnum:]_.-])${2}([^[:alnum:]_.-]|\$)"
}

update_dual_marketplace_plugin() { # repo claude_marketplace codex_marketplace plugin
  local repo="$1"
  local claude_mkt="$2"
  local codex_mkt="$3"
  local plugin="$4"
  local codex_state

  plugins_section "Claude Code (marketplace ${claude_mkt})"
  if marketplace_listed claude "$claude_mkt"; then
    plugins_info "updating marketplace ${claude_mkt}"
    claude plugin marketplace update "$claude_mkt"
  else
    plugins_info "adding marketplace ${claude_mkt} (${repo})"
    claude plugin marketplace add "$repo"
  fi
  if claude plugin list 2>/dev/null | grep -qF "${plugin}@${claude_mkt}"; then
    plugins_info "updating plugin ${plugin}@${claude_mkt}"
    claude plugin update "${plugin}@${claude_mkt}"
  else
    plugins_info "installing plugin ${plugin}@${claude_mkt}"
    claude plugin install "${plugin}@${claude_mkt}"
  fi

  plugins_section "Codex (marketplace ${codex_mkt})"
  if marketplace_listed codex "$codex_mkt"; then
    plugins_info "upgrading marketplace ${codex_mkt}"
    codex_marketplace_upgrade "$codex_mkt"
  else
    plugins_info "adding marketplace ${codex_mkt} (${repo})"
    codex plugin marketplace add "$repo"
  fi
  codex_state="$(codex plugin list -m "$codex_mkt" --json 2>/dev/null \
    | jq -r --arg id "${plugin}@${codex_mkt}" \
        '.installed[]? | select(.pluginId == $id and .installed == true)
         | if .enabled then "enabled" else "disabled" end' 2>/dev/null \
    | head -1)" || codex_state=""
  case "$codex_state" in
    enabled)
      plugins_info "${plugin}@${codex_mkt} already installed and enabled"
      ;;
    disabled)
      # codex plugin has no enable subcommand, and `add` errors on an
      # installed plugin — fail loud instead of dying on a confusing add.
      plugins_warn "${plugin}@${codex_mkt} is installed but disabled; re-enable it in Codex config"
      return 1
      ;;
    *)
      plugins_info "installing plugin ${plugin}@${codex_mkt}"
      codex plugin add "${plugin}@${codex_mkt}"
      ;;
  esac
}
