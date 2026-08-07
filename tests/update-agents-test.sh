#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

run_case() {
  local layout="$1"
  local case_root="$TEST_ROOT/$layout"
  local bin="$case_root/bin"
  local npm_prefix="$case_root/npm-prefix"
  local npm_log="$case_root/npm.log"
  local codex_package codex_bin_dir npm_windows_prefix=""

  case "$layout" in
    unix)
      codex_package="$npm_prefix/lib/node_modules/@openai/codex/bin/codex.js"
      codex_bin_dir="$npm_prefix/bin"
      ;;
    windows)
      codex_package="$npm_prefix/node_modules/@openai/codex/bin/codex.js"
      codex_bin_dir="$npm_prefix"
      npm_windows_prefix='C:\Users\Test\npm'
      ;;
  esac
  mkdir -p "$bin" "$codex_bin_dir" "$(dirname "$codex_package")"

  cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo '2.1.223 (Claude Code)' ;;
  update) exit 0 ;;
esac
EOF

  cat > "$bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPM_LOG"
case "$*" in
  'prefix -g')
    if [ -n "${NPM_WINDOWS_PREFIX:-}" ]; then
      printf '%s\r\n' "$NPM_WINDOWS_PREFIX"
    else
      printf '%s\n' "$NPM_PREFIX"
    fi
    ;;
  'view @openai/codex version') echo '0.146.1' ;;
  *) exit 99 ;;
esac
EOF

  if [ "$layout" = "windows" ]; then
    cat > "$bin/cygpath" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-u" ] && [ "$2" = "$NPM_WINDOWS_PREFIX" ]
printf '%s\n' "$NPM_PREFIX"
EOF
    chmod +x "$bin/cygpath"
  fi

  cat > "$codex_package" <<'EOF'
#!/usr/bin/env bash
echo 'codex-cli 0.146.1'
EOF

  chmod +x "$bin/claude" "$bin/npm" "$codex_package"
  if [ "$layout" = "unix" ]; then
    rmdir "$codex_bin_dir"
  else
    touch "$codex_bin_dir/.codex-interrupted"
    touch "$codex_bin_dir/.codex.cmd-interrupted"
  fi

  PATH="$bin:$codex_bin_dir:/usr/bin:/bin" \
    NPM_PREFIX="$npm_prefix" \
    NPM_WINDOWS_PREFIX="$npm_windows_prefix" \
    NPM_LOG="$npm_log" \
    bash "$REPO_ROOT/agent-tooling/update-agents.sh" > "$case_root/output"

  test -x "$codex_bin_dir/codex"
  test ! -e "$codex_bin_dir/.codex-interrupted"
  if rg -F 'install -g @openai/codex' "$npm_log" >/dev/null; then
    echo "unexpected Codex reinstall for $layout layout" >&2
    return 1
  fi
  rg -F 'codex package present but bin link missing; relinking' "$case_root/output" >/dev/null
  rg -F 'codex already up to date; skipping npm install' "$case_root/output" >/dev/null

  if [ "$layout" = "unix" ]; then
    test -L "$codex_bin_dir/codex"
    test "$(readlink "$codex_bin_dir/codex")" = '../lib/node_modules/@openai/codex/bin/codex.js'
  else
    test -f "$codex_bin_dir/codex.cmd"
    test ! -e "$codex_bin_dir/.codex.cmd-interrupted"
    rg -F 'node "%~dp0node_modules\@openai\codex\bin\codex.js" %*' \
      "$codex_bin_dir/codex.cmd" >/dev/null
  fi

  if [ "$layout" = "unix" ]; then
    rm "$codex_bin_dir/codex"
  fi
  cat > "$codex_bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
# preserved launcher
echo 'codex-cli 0.146.1'
EOF
  chmod +x "$codex_bin_dir/codex"
  if [ "$layout" = "windows" ]; then
    printf '%s\r\n' '@REM preserved launcher' > "$codex_bin_dir/codex.cmd"
  fi

  PATH="$bin:/usr/bin:/bin" \
    NPM_PREFIX="$npm_prefix" \
    NPM_WINDOWS_PREFIX="$npm_windows_prefix" \
    NPM_LOG="$npm_log" \
    bash "$REPO_ROOT/agent-tooling/update-agents.sh" > "$case_root/restricted-output" || true

  rg -F '# preserved launcher' "$codex_bin_dir/codex" >/dev/null
  if [ "$layout" = "windows" ]; then
    rg -F '@REM preserved launcher' "$codex_bin_dir/codex.cmd" >/dev/null
  fi

  if [ "$layout" = "unix" ]; then
    rm "$codex_bin_dir/codex"
    rmdir "$codex_bin_dir"
    chmod 555 "$npm_prefix"
    if PATH="$bin:/usr/bin:/bin" \
      NPM_PREFIX="$npm_prefix" \
      NPM_WINDOWS_PREFIX="$npm_windows_prefix" \
      NPM_LOG="$npm_log" \
      bash "$REPO_ROOT/agent-tooling/update-agents.sh" > "$case_root/write-failure-output" 2>&1; then
      echo "unexpected success with unwritable npm prefix" >&2
      return 1
    fi
    chmod 755 "$npm_prefix"
    rg -F 'could not restore a runnable codex launcher; reinstalling' \
      "$case_root/write-failure-output" >/dev/null
    if ! rg -F 'codex install failed' "$case_root/write-failure-output" >/dev/null; then
      cat "$case_root/write-failure-output" >&2
      return 1
    fi
    rg -F 'Agent CLIs done' "$case_root/write-failure-output" >/dev/null
  fi
}

run_case unix
run_case windows

echo 'update-agents tests passed'
