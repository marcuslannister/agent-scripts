#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_UNDER_TEST:-$REPO_ROOT/scripts/update-cc-plugins.sh}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FAKE_HOME="$TMPDIR/home"
BIN="$TMPDIR/bin"
LOG="$TMPDIR/updates.log"
mkdir -p "$FAKE_HOME/.claude/plugins" "$BIN"
printf '{"plugins":{"claude-mem@thedotmack":{},"waza@waza":{}}}\n' \
  > "$FAKE_HOME/.claude/plugins/installed_plugins.json"

cat > "$BIN/jq" <<'FAKE_JQ'
#!/usr/bin/env bash
printf 'claude-mem@thedotmack\r\nwaza@waza\r\n'
FAKE_JQ

cat > "$BIN/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail

if [ "$*" = "plugin marketplace update" ]; then
  exit 0
fi

if [ "$1" = "plugin" ] && [ "$2" = "update" ]; then
  plugin="$3"
  printf '%s\n' "$plugin" >> "$FAKE_CLAUDE_LOG"
  case "$plugin" in
    *$'\r'*)
      printf 'Plugin not found in marketplace: %s\n' "$plugin" >&2
      exit 1
      ;;
  esac
  exit 0
fi

printf 'unexpected claude call: %s\n' "$*" >&2
exit 1
FAKE_CLAUDE

chmod +x "$BIN/jq" "$BIN/claude"

if ! HOME="$FAKE_HOME" PATH="$BIN:$PATH" FAKE_CLAUDE_LOG="$LOG" \
  "$SCRIPT" > "$TMPDIR/out" 2>&1; then
  cat "$TMPDIR/out" >&2
  exit 1
fi

printf '%s\n' 'claude-mem@thedotmack' 'waza@waza' > "$TMPDIR/expected"
if ! cmp -s "$TMPDIR/expected" "$LOG"; then
  echo "FAIL: plugin update keys were not clean" >&2
  echo "Expected:" >&2
  cat "$TMPDIR/expected" >&2
  echo "Actual:" >&2
  cat "$LOG" >&2
  exit 1
fi

grep -F 'Results: 2 updated, 0 skipped, 0 failed' "$TMPDIR/out" >/dev/null
if grep -q $'\r' "$LOG"; then
  echo "FAIL: plugin update key retained a carriage return" >&2
  exit 1
fi

echo "update-cc-plugins tests passed"
