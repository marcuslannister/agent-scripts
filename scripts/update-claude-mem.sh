#!/usr/bin/env bash
set -euo pipefail

# Install/update claude-mem (github.com/thedotmack/claude-mem) for Claude Code
# and Codex through each CLI's own plugin marketplace — no npx installer, so
# both tools manage it like any other marketplace plugin and share one worker
# and database (~/.claude-mem). Marketplace names come from the repo manifests:
# "thedotmack" (.claude-plugin/marketplace.json) for Claude Code and
# "claude-mem-local" (.agents/plugins/marketplace.json) for Codex.
# Re-runnable; exits non-zero on failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-plugins.sh"

find_claude_mem_bun() {
  local candidate
  local found

  for candidate in \
    "$HOME"/scoop/apps/bun/*/bun.exe \
    "$HOME/scoop/apps/bun/current/bun.exe" \
    "$HOME/scoop/shims/bun" \
    "$HOME/scoop/shims/bun.exe" \
    "$HOME/.bun/bin/bun" \
    "$HOME/.bun/bin/bun.exe" \
    /usr/local/bin/bun \
    /opt/homebrew/bin/bun \
    /home/linuxbrew/.linuxbrew/bin/bun
  do
    [ -e "$candidate" ] || continue
    if "$candidate" --version >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if found="$(command -v bun 2>/dev/null)" && "$found" --version >/dev/null 2>&1; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

find_claude_mem_uv() {
  local command_name="$1"
  local candidate
  local found

  for candidate in \
    "$HOME"/scoop/apps/uv/*/"${command_name}.exe" \
    "$HOME/scoop/apps/uv/current/${command_name}.exe" \
    "$HOME/scoop/shims/${command_name}" \
    "$HOME/scoop/shims/${command_name}.exe" \
    "$HOME/.local/bin/${command_name}" \
    /usr/local/bin/"$command_name" \
    /opt/homebrew/bin/"$command_name" \
    /home/linuxbrew/.linuxbrew/bin/"$command_name"
  do
    [ -e "$candidate" ] || continue
    if "$candidate" --version >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if found="$(command -v "$command_name" 2>/dev/null)" && "$found" --version >/dev/null 2>&1; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

require_claude_mem_bun() {
  local bun_path

  if bun_path="$(find_claude_mem_bun)"; then
    plugins_info "bun available for claude-mem hooks: ${bun_path}"
    return 0
  fi

  plugins_warn "claude-mem requires runnable Bun for its hooks, but no working bun executable was found"
  plugins_warn "install or repair Bun first, then rerun this script: https://bun.sh/docs/installation"
  return 1
}

require_claude_mem_uv() {
  local uv_path
  local uvx_path

  if uv_path="$(find_claude_mem_uv uv)" && uvx_path="$(find_claude_mem_uv uvx)"; then
    plugins_info "uv available for claude-mem vector search: ${uv_path}"
    plugins_info "uvx available for claude-mem vector search: ${uvx_path}"
    return 0
  fi

  plugins_warn "claude-mem requires runnable uv for vector search, but uv/uvx was not found"
  plugins_warn "install or repair Astral uv first, then rerun this script; on Windows with Scoop: scoop install uv"
  return 1
}

require_claude_mem_bun
require_claude_mem_uv
update_dual_marketplace_plugin "thedotmack/claude-mem" thedotmack claude-mem-local claude-mem

plugins_section "claude-mem done"
