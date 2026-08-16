#!/usr/bin/env bash
set -euo pipefail

# Plugin refresh helper (ADR-0009): best-effort native updates that honor
# manual-upgrade markers (ADR-0007) and never fail the run.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/agent-tooling"
BIN="$TMP_ROOT/bin"
STATE="$TMP_ROOT/state"
mkdir -p "$FIXTURE" "$BIN" "$STATE"
cp "$REPO_ROOT/agent-tooling/update-plugins.sh" "$FIXTURE/"

cat > "$FIXTURE/sources.json" <<'JSON'
{
  "version": 2,
  "sources": [
    {
      "id": "waza",
      "classification": "dual-plugin",
      "repo": "tw93/Waza",
      "plugin": {
        "name": "waza",
        "marketplaces": { "claude": "waza", "codex": "waza" }
      }
    },
    {
      "id": "claude-mem",
      "classification": "dual-plugin",
      "repo": "thedotmack/claude-mem",
      "plugin": {
        "name": "claude-mem",
        "marketplaces": { "claude": "thedotmack", "codex": "claude-mem-local" },
        "codexUpgrade": "manual"
      }
    },
    {
      "id": "absent-plugin",
      "classification": "plugin-claude-only",
      "repo": "example/absent",
      "plugin": {
        "name": "absent",
        "marketplaces": { "claude": "absent-marketplace" }
      }
    }
  ]
}
JSON

cat > "$BIN/claude" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "claude $*" >> "$PLUGIN_LOG"
case "$*" in
  'plugin list --json')
    printf '[{"id":"waza@waza"},{"id":"claude-mem@thedotmack"}]\n'
    ;;
  'plugin marketplace update thedotmack')
    printf 'boom: marketplace update failed\n' >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
BASH
cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "codex $*" >> "$PLUGIN_LOG"
case "$*" in
  'plugin list --json')
    printf '{"installed":[{"pluginId":"waza@waza","installed":true}]}\n'
    ;;
  *) exit 0 ;;
esac
BASH
chmod +x "$BIN/claude" "$BIN/codex"

PLUGIN_LOG="$STATE/calls.log"
: > "$PLUGIN_LOG"
PLUGIN_LOG="$PLUGIN_LOG" PATH="$BIN:$PATH" "$FIXTURE/update-plugins.sh" \
  > "$STATE/out" 2> "$STATE/err"

# Healthy Claude plugin: marketplace update then plugin update.
rg -Fx 'claude plugin marketplace update waza' "$PLUGIN_LOG" >/dev/null
rg -Fx 'claude plugin update waza@waza' "$PLUGIN_LOG" >/dev/null

# Manual-upgrade marker: the doomed Codex marketplace call never runs.
rg -q 'codex plugin marketplace upgrade claude-mem-local' "$PLUGIN_LOG" \
  && { echo "FAIL: manual-upgrade marketplace was upgraded anyway" >&2; exit 1; }
rg -F 'manual-upgrade (ADR-0007)' "$STATE/out" >/dev/null

# Codex refreshes what it actually has installed.
rg -Fx 'codex plugin marketplace upgrade waza' "$PLUGIN_LOG" >/dev/null
rg -Fx 'codex plugin add waza@waza' "$PLUGIN_LOG" >/dev/null

# A plugin that is not installed is reported, never installed silently.
rg -q 'claude plugin install' "$PLUGIN_LOG" \
  && { echo "FAIL: helper installed a plugin on its own" >&2; exit 1; }
rg -F 'absent-plugin: Claude plugin absent@absent-marketplace not installed' "$STATE/out" >/dev/null

# A failing marketplace update is one warning, and the run still succeeds.
rg -F 'claude-mem: Claude marketplace update failed' "$STATE/err" >/dev/null
rg -q 'claude plugin update claude-mem@thedotmack' "$PLUGIN_LOG" \
  && { echo "FAIL: plugin update ran after its marketplace update failed" >&2; exit 1; }

# An unreadable inventory is reported, and no plugin is called "not installed".
cat > "$BIN/claude" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "claude $*" >> "$PLUGIN_LOG"
case "$*" in
  'plugin list --json')
    printf 'error: could not read plugin state\n' >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
BASH
cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "codex $*" >> "$PLUGIN_LOG"
case "$*" in
  'plugin list --json') printf 'not json at all\n' ;;
  *) exit 0 ;;
esac
BASH
chmod +x "$BIN/claude" "$BIN/codex"
: > "$PLUGIN_LOG"
PLUGIN_LOG="$PLUGIN_LOG" PATH="$BIN:$PATH" "$FIXTURE/update-plugins.sh" \
  > "$STATE/broken.out" 2> "$STATE/broken.err"
rg -F 'Claude plugin inventory failed' "$STATE/broken.err" >/dev/null
rg -F 'Codex plugin inventory returned invalid JSON' "$STATE/broken.err" >/dev/null
rg -q 'not installed' "$STATE/broken.out" \
  && { echo "FAIL: unreadable inventory reported plugins as not installed" >&2; exit 1; }
rg -q 'plugin update|plugin add' "$PLUGIN_LOG" \
  && { echo "FAIL: plugin refresh ran without a readable inventory" >&2; exit 1; }

# Missing CLIs are skipped, not fatal.
: > "$PLUGIN_LOG"
PLUGIN_LOG="$PLUGIN_LOG" PATH="/usr/bin:/bin" "$FIXTURE/update-plugins.sh" \
  > "$STATE/nocli.out" 2>&1
rg -F 'claude CLI not found' "$STATE/nocli.out" >/dev/null
rg -F 'codex CLI not found' "$STATE/nocli.out" >/dev/null

echo "update-plugins tests passed"
