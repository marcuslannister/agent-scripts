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
# Keep the real ~/.claude hooks out of every run below.
export HOME="$TMP_ROOT/home"
cp "$REPO_ROOT/agent-tooling/update-plugins.sh" "$REPO_ROOT/agent-tooling/nowledge-lean-codex-pi.sh" "$FIXTURE/"

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

# Windows jq.exe writes CRLF; no \r may leak into marketplace names or ids.
CRLF_BIN="$TMP_ROOT/crlf-bin"
mkdir -p "$CRLF_BIN"
printf '#!/usr/bin/env bash\n%q "$@" | sed "s/\\$/\\r/"\n' "$(command -v jq)" > "$CRLF_BIN/jq"
chmod +x "$CRLF_BIN/jq"
: > "$PLUGIN_LOG"
PLUGIN_LOG="$PLUGIN_LOG" PATH="$CRLF_BIN:$BIN:$PATH" "$FIXTURE/update-plugins.sh" >/dev/null 2>&1
rg -Fx 'claude plugin marketplace update waza' "$PLUGIN_LOG" >/dev/null
rg -Fx 'claude plugin update waza@waza' "$PLUGIN_LOG" >/dev/null
rg -Fx 'codex plugin add waza@waza' "$PLUGIN_LOG" >/dev/null

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

# The nowledge-mem, ponytail, and eli5 lean patches run after plugin refresh when
# their hooks exist, and a failed patch is one warning, not a failed run.
mkdir -p "$HOME/.claude/hooks"
printf '%s\n' 'echo nowledge ran >> "$PLUGIN_LOG"' > "$HOME/.claude/hooks/nowledge-lean.sh"
printf '%s\n' 'echo ponytail ran >> "$PLUGIN_LOG"' > "$HOME/.claude/hooks/ponytail-lean.sh"
printf '%s\n' 'echo eli5 ran >> "$PLUGIN_LOG"' > "$HOME/.claude/hooks/eli5-lean.sh"
: > "$PLUGIN_LOG"
PLUGIN_LOG="$PLUGIN_LOG" PATH="/usr/bin:/bin" "$FIXTURE/update-plugins.sh" \
  > "$STATE/lean.out" 2>&1
rg -Fx 'nowledge ran' "$PLUGIN_LOG" >/dev/null
rg -Fx 'ponytail ran' "$PLUGIN_LOG" >/dev/null
rg -Fx 'eli5 ran' "$PLUGIN_LOG" >/dev/null
rg -F 'nowledge: lean context patch applied' "$STATE/lean.out" >/dev/null
rg -F 'ponytail: lean context patch applied' "$STATE/lean.out" >/dev/null
rg -F 'eli5: lean context patch applied' "$STATE/lean.out" >/dev/null
printf '%s\n' 'echo anchor missing >&2; exit 1' > "$HOME/.claude/hooks/nowledge-lean.sh"
PLUGIN_LOG="$PLUGIN_LOG" PATH="/usr/bin:/bin" "$FIXTURE/update-plugins.sh" \
  > "$STATE/lean2.out" 2> "$STATE/lean.err"
rg -F 'nowledge: lean context patch failed: anchor missing' "$STATE/lean.err" >/dev/null
rg -F 'ponytail: lean context patch applied' "$STATE/lean2.out" >/dev/null

# The Codex nowledge-mem patch sends one note at start and nothing on a prompt
# (a thread resume still passes), changes nothing on a second run, and
# NMEM_FULL_CONTEXT=1 restores the plugin's own output.
CODEX_HOOK="$HOME/.codex/plugins/cache/nowledge-community/nowledge-mem/9.9.9/hooks/nmem-context.py"
mkdir -p "${CODEX_HOOK%/*}"
cat > "$CODEX_HOOK" <<'PY'
import json, os, sys
PROMPT_ROUTING_GUIDANCE = "per prompt text"
def _write_hook_response(event, text):
    print(json.dumps({"event": event, "text": text}))
def main(payload):
    event_name = payload["hook_event_name"]
    resume_context = payload.get("resume", "")
    if event_name == "UserPromptSubmit":
        guidance = PROMPT_ROUTING_GUIDANCE
    elif event_name == "SubagentStart":
        guidance = "subagent text"
    else:
        guidance = "full start text"
    _write_hook_response(event_name, guidance)
    return 0
main(json.loads(sys.stdin.read()))
PY
codex_hook() { printf '%s' "$1" | python3 "$CODEX_HOOK"; }
bash "$FIXTURE/nowledge-lean-codex-pi.sh"
cp "$CODEX_HOOK" "$STATE/codex-hook.once"
bash "$FIXTURE/nowledge-lean-codex-pi.sh"
cmp -s "$CODEX_HOOK" "$STATE/codex-hook.once" \
  || { echo "FAIL: second codex lean patch run changed the file" >&2; exit 1; }
codex_hook '{"hook_event_name":"SessionStart"}' | rg -F 'search first: nmem --json m search' >/dev/null
[ -z "$(codex_hook '{"hook_event_name":"UserPromptSubmit"}')" ] \
  || { echo "FAIL: lean Codex hook still adds text on a prompt" >&2; exit 1; }
codex_hook '{"hook_event_name":"UserPromptSubmit","resume":"thread context"}' | rg -F 'thread context' >/dev/null
codex_hook '{"hook_event_name":"SubagentStart"}' | rg -F 'subagent text' >/dev/null
printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | NMEM_FULL_CONTEXT=1 python3 "$CODEX_HOOK" \
  | rg -F 'per prompt text' >/dev/null
printf '%s\n' 'print("upstream changed")' > "$CODEX_HOOK"
PLUGIN_LOG="$PLUGIN_LOG" PATH="/usr/bin:/bin" "$FIXTURE/update-plugins.sh" \
  > "$STATE/codexlean.out" 2> "$STATE/codexlean.err"
rg -F 'nowledge (Codex, Pi): lean context patch failed: nowledge-lean: anchor not found' "$STATE/codexlean.err" >/dev/null
[ "$(cat "$CODEX_HOOK")" = 'print("upstream changed")' ] \
  || { echo "FAIL: codex lean patch edited a file without its anchor" >&2; exit 1; }

# The Pi nowledge-mem patch swaps the system-prompt bundle for the note, skips
# the nmem reads that fill it, and changes nothing on a second run. The fixture
# is TypeScript, so the test checks the text, not the behavior.
PI_EXT="$HOME/.pi/agent/npm/node_modules/nowledge-mem-pi/extensions/nowledge-mem.ts"
rm -f "$CODEX_HOOK" # its anchor-less fixture would fail the runs below
mkdir -p "${PI_EXT%/*}"
cat > "$PI_EXT" <<'TS'
async function refreshStartupContext(ctx: ExtensionContext): Promise<void> {
	const key = startupContextCacheKey(ctx);
}

async function appendMemoryContext(systemPrompt: string, ctx: ExtensionContext): Promise<string> {
	return `${systemPrompt}\n\nBUNDLE`;
}
TS
bash "$FIXTURE/nowledge-lean-codex-pi.sh"
cp "$PI_EXT" "$STATE/pi-ext.once"
bash "$FIXTURE/nowledge-lean-codex-pi.sh"
cmp -s "$PI_EXT" "$STATE/pi-ext.once" \
  || { echo "FAIL: second pi lean patch run changed the file" >&2; exit 1; }
[ "$(rg -c 'NMEM_FULL_CONTEXT' "$PI_EXT")" = 2 ]
rg -F 'return systemPrompt + "\n\n" + "[Nowledge Mem] Memory is available.' "$PI_EXT" >/dev/null
printf '%s\n' 'export default function () {}' > "$PI_EXT"
PLUGIN_LOG="$PLUGIN_LOG" PATH="/usr/bin:/bin" "$FIXTURE/update-plugins.sh" \
  > "$STATE/pilean.out" 2> "$STATE/pilean.err"
rg -F "nowledge-lean: anchor not found in $PI_EXT" "$STATE/pilean.err" >/dev/null
[ "$(cat "$PI_EXT")" = 'export default function () {}' ] \
  || { echo "FAIL: pi lean patch edited a file without its anchor" >&2; exit 1; }

echo "update-plugins tests passed"
