#!/usr/bin/env bash
set -euo pipefail

# Update the coding-agent CLIs: Claude Code (native), Codex (npm), and Pi.
# Tries all installed CLIs even if one fails; exits non-zero if any update failed.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

fail=0

section "Claude Code CLI"
if ! command -v claude >/dev/null 2>&1; then
  info "claude not found; installing"
  if curl -fsSL https://claude.ai/install.sh | bash && command -v claude >/dev/null 2>&1; then
    info "installed: $(claude --version 2>/dev/null || echo unknown)"
  else
    warn "claude install failed"
    fail=1
  fi
else
  info "current: $(claude --version 2>/dev/null || echo unknown)"
  if claude update; then
    info "now:     $(claude --version 2>/dev/null || echo unknown)"
  else
    warn "claude update failed"
    fail=1
  fi
fi

section "Codex CLI"
# Repair a half-finished `npm install -g @openai/codex`. npm retires the Codex
# launcher at the start of reify and only restores it once the ~126MB platform
# tarball finishes extracting, so a run killed mid-download leaves codex off
# PATH and the next run downloads the tarball again. Restore the launcher first
# so the up-to-date check below can skip the download entirely.
npm_prefix="$(npm prefix -g 2>/dev/null || true)"
npm_prefix="${npm_prefix%$'\r'}"
case "$npm_prefix" in
  [A-Za-z]:\\*|[A-Za-z]:/*)
    if command -v cygpath >/dev/null 2>&1 \
      && npm_prefix_unix="$(cygpath -u "$npm_prefix" 2>/dev/null)"; then
      npm_prefix="$npm_prefix_unix"
    fi
    ;;
esac
codex_package=""
codex_bin_dir=""
codex_layout=""
if [ -f "$npm_prefix/lib/node_modules/@openai/codex/bin/codex.js" ]; then
  codex_package="$npm_prefix/lib/node_modules/@openai/codex/bin/codex.js"
  codex_bin_dir="$npm_prefix/bin"
  codex_layout="unix"
elif [ -f "$npm_prefix/node_modules/@openai/codex/bin/codex.js" ]; then
  codex_package="$npm_prefix/node_modules/@openai/codex/bin/codex.js"
  codex_bin_dir="$npm_prefix"
  codex_layout="windows"
fi

codex_launcher_missing=0
case "$codex_layout" in
  unix) [ -e "$codex_bin_dir/codex" ] || codex_launcher_missing=1 ;;
  windows)
    if [ ! -e "$codex_bin_dir/codex" ] || [ ! -e "$codex_bin_dir/codex.cmd" ]; then
      codex_launcher_missing=1
    fi
    ;;
esac

if [ -n "$codex_package" ] && [ "$codex_launcher_missing" -eq 1 ]; then
  info "codex package present but bin link missing; relinking"
  codex_launchers=()
  codex_relink_failed=0
  if ! mkdir -p "$codex_bin_dir"; then
    codex_relink_failed=1
  elif [ "$codex_layout" = "unix" ]; then
    if ln -sf ../lib/node_modules/@openai/codex/bin/codex.js "$codex_bin_dir/codex"; then
      codex_launchers+=("$codex_bin_dir/codex")
    else
      codex_relink_failed=1
    fi
  else
    if [ ! -e "$codex_bin_dir/codex" ]; then
      if printf '%s\n' '#!/bin/sh' \
          'exec "$(dirname "$0")/node_modules/@openai/codex/bin/codex.js" "$@"' \
          > "$codex_bin_dir/codex" \
        && chmod +x "$codex_bin_dir/codex"; then
        codex_launchers+=("$codex_bin_dir/codex")
      else
        codex_relink_failed=1
      fi
    fi
    if [ ! -e "$codex_bin_dir/codex.cmd" ]; then
      if printf '%s\r\n' '@ECHO off' \
          'node "%~dp0node_modules\@openai\codex\bin\codex.js" %*' \
          > "$codex_bin_dir/codex.cmd"; then
        codex_launchers+=("$codex_bin_dir/codex.cmd")
      else
        codex_relink_failed=1
      fi
    fi
  fi
  hash -r 2>/dev/null || true
  if [ "$codex_relink_failed" -eq 0 ] \
    && "$codex_bin_dir/codex" --version >/dev/null 2>&1; then
    info "relinked codex"
    rm -f "$codex_bin_dir"/.codex-* \
      "$codex_bin_dir"/.codex.cmd-* \
      "$codex_bin_dir"/.codex.ps1-*
  else
    # The package tree is truncated or the launcher cannot be written. Let npm
    # perform the normal install and report any failure through the path below.
    warn "could not restore a runnable codex launcher; reinstalling"
    for codex_launcher in "${codex_launchers[@]-}"; do
      [ -n "$codex_launcher" ] || continue
      rm -f "$codex_launcher" || true
    done
    hash -r 2>/dev/null || true
  fi
fi

if ! command -v codex >/dev/null 2>&1; then
  info "codex not found; installing"
  warn "this pulls a ~126MB tarball that cannot resume — do not interrupt it,"
  warn "and do not run this step under a short command timeout"
  if npm install -g @openai/codex && command -v codex >/dev/null 2>&1; then
    info "installed: $(codex --version 2>/dev/null || echo unknown)"
  else
    warn "codex install failed"
    fail=1
  fi
else
  current_codex="$(codex --version 2>/dev/null || echo unknown)"
  current_codex_version="${current_codex##* }"
  latest_codex_version="$(npm view @openai/codex version 2>/dev/null || true)"
  latest_codex_version="${latest_codex_version//$'\r'/}"
  info "current: $current_codex"
  if [ -n "$latest_codex_version" ] && [ "$current_codex_version" = "$latest_codex_version" ]; then
    info "latest:  $latest_codex_version"
    info "codex already up to date; skipping npm install"
    info "now:     $(codex --version 2>/dev/null || echo unknown)"
  elif npm install -g @openai/codex; then
    info "now:     $(codex --version 2>/dev/null || echo unknown)"
  else
    warn "codex update failed"
    fail=1
  fi
fi

section "Pi CLI"
if ! command -v pi >/dev/null 2>&1; then
  info "pi not found; installing"
  if curl -fsSL https://pi.dev/install.sh | sh \
    && command -v pi >/dev/null 2>&1; then
    info "pi installed"
  else
    warn "pi install failed"
    fail=1
  fi
elif pi update; then
  info "pi update complete"
else
  warn "pi update failed"
  fail=1
fi

section "Agent CLIs done"
exit $fail
