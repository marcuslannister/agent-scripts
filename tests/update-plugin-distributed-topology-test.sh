#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/waza"
BIN="$FIXTURE/bin"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/home" "$FIXTURE/runtime" "$BIN"
cp "$REPO_ROOT/scripts/update-skill-topology.sh" "$FIXTURE/scripts/"
cp -R "$REPO_ROOT/scripts/distribution-topology" "$FIXTURE/scripts/"

cat > "$FIXTURE/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "waza",
      "classification": "plugin-both",
      "defaultDestinations": ["claude", "codex"],
      "overrides": {"waza": ["claude", "codex"]}
    }
  ]
}
JSON

cat > "$FIXTURE/scripts/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "waza",
    "classification": "plugin-both",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/plugin-both.sh",
    "stateInspection": "adapter",
    "plugin": {
      "name": "waza",
      "repo": "tw93/Waza",
      "marketplaces": {"claude": "waza", "codex": "waza"}
    }
  }
]
JSON

printf '[]\n' > "$FIXTURE/home/claude-plugins.json"
printf '[]\n' > "$FIXTURE/home/claude-marketplaces.json"
printf '{"installed":[]}\n' > "$FIXTURE/home/codex-plugins.json"
printf '{"marketplaces":[]}\n' > "$FIXTURE/home/codex-marketplaces.json"

cat > "$BIN/claude" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    cat "$HOME/claude-plugins.json"
    ;;
  'plugin marketplace list --json')
    cat "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace add tw93/Waza')
    printf '[{"name":"waza"}]\n' > "$HOME/claude-marketplaces.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin marketplace update waza')
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    if [ "${FAKE_CLAUDE_MARKETPLACE_FAIL:-0}" = 1 ]; then
      printf 'fixture Claude marketplace failure\n' >&2
      exit 1
    fi
    ;;
  'plugin install waza@waza')
    printf '[{"id":"waza@waza","version":"1.0.0","enabled":true}]\n' > "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin enable waza@waza')
    jq 'map(if .id == "waza@waza" then .enabled = true else . end)' \
      "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
    mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin update waza@waza')
    if [ -n "${FAKE_PLUGIN_UPDATE_VERSION:-}" ]; then
      jq --arg version "$FAKE_PLUGIN_UPDATE_VERSION" \
        'map(if .id == "waza@waza" then .version = $version else . end)' \
        "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
      mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    fi
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  *)
    printf 'unexpected claude call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    cat "$HOME/codex-plugins.json"
    ;;
  'plugin marketplace list --json')
    cat "$HOME/codex-marketplaces.json"
    ;;
  'plugin marketplace add tw93/Waza')
    printf '{"marketplaces":[{"name":"waza"}]}\n' > "$HOME/codex-marketplaces.json"
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    ;;
  'plugin marketplace upgrade waza')
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    if [ "${FAKE_CODEX_MARKETPLACE_FAIL:-0}" = 1 ]; then
      printf 'fixture Codex marketplace failure\n' >&2
      exit 1
    fi
    if [ -n "${FAKE_PLUGIN_UPDATE_VERSION:-}" ]; then
      jq --arg version "$FAKE_PLUGIN_UPDATE_VERSION" \
        '.installed |= map(if .pluginId == "waza@waza" then .version = $version else . end)' \
        "$HOME/codex-plugins.json" > "$HOME/codex-plugins.tmp"
      mv "$HOME/codex-plugins.tmp" "$HOME/codex-plugins.json"
    fi
    ;;
  'plugin add waza@waza')
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    if [ "${FAKE_CODEX_INSTALL_FAIL:-0}" = 1 ]; then
      printf 'fixture Codex install failure\n' >&2
      exit 1
    fi
    printf '{"installed":[{"pluginId":"waza@waza","marketplaceName":"waza","version":"1.0.0","installed":true,"enabled":true}]}\n' > "$HOME/codex-plugins.json"
    ;;
  'plugin remove waza@waza')
    printf '{"installed":[]}\n' > "$HOME/codex-plugins.json"
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    ;;
  *)
    printf 'unexpected codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH
chmod +x "$BIN/claude" "$BIN/codex"

COMMAND="$FIXTURE/scripts/update-skill-topology.sh"
MISSING_METADATA_FIXTURE="$TMP_ROOT/missing-plugin-metadata"
cp -R "$FIXTURE" "$MISSING_METADATA_FIXTURE"
jq '.[0] |= del(.plugin)' \
  "$MISSING_METADATA_FIXTURE/scripts/distribution-topology/registry.json" > "$MISSING_METADATA_FIXTURE/registry.tmp"
mv "$MISSING_METADATA_FIXTURE/registry.tmp" "$MISSING_METADATA_FIXTURE/scripts/distribution-topology/registry.json"
set +e
HOME="$MISSING_METADATA_FIXTURE/home" TMPDIR="$MISSING_METADATA_FIXTURE/runtime" \
PATH="$MISSING_METADATA_FIXTURE/bin:$PATH" \
  "$MISSING_METADATA_FIXTURE/scripts/update-skill-topology.sh" --check --json > "$MISSING_METADATA_FIXTURE/result.json"
missing_metadata_exit=$?
set -e
test "$missing_metadata_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("requires plugin metadata for a plugin source"))
' "$MISSING_METADATA_FIXTURE/result.json" >/dev/null
jq -e '. == []' "$MISSING_METADATA_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed == []' "$MISSING_METADATA_FIXTURE/home/codex-plugins.json" >/dev/null

if ! HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/first.json"; then
  cat "$FIXTURE/first.json" >&2
  exit 1
fi
jq -e '
  .status == "reconciled" and
  ([.plan[] | {sourceId, skill, destinations}] == [{
    "sourceId":"waza",
    "skill":"waza",
    "destinations":["claude","codex"]
  }]) and
  ([.changes[] | {action, sourceId, skill, destination}] == [
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"claude"},
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"codex"}
  ]) and
  .errors == [] and .decisions == []
' "$FIXTURE/first.json" >/dev/null
grep -Fx 'plugin marketplace add tw93/Waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin install waza@waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin marketplace add tw93/Waza' "$FIXTURE/home/codex-mutations.log" >/dev/null
grep -Fx 'plugin add waza@waza' "$FIXTURE/home/codex-mutations.log" >/dev/null

cp "$FIXTURE/home/claude-mutations.log" "$FIXTURE/claude-mutations-before-check"
cp "$FIXTURE/home/codex-mutations.log" "$FIXTURE/codex-mutations-before-check"
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --check --json > "$FIXTURE/check.json"
jq -e '.status == "clean" and .changes == [] and .errors == []' "$FIXTURE/check.json" >/dev/null
cmp -s "$FIXTURE/claude-mutations-before-check" "$FIXTURE/home/claude-mutations.log"
cmp -s "$FIXTURE/codex-mutations-before-check" "$FIXTURE/home/codex-mutations.log"

HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/second.json"
jq -e '.status == "reconciled" and .changes == [] and .errors == [] and .decisions == []' \
  "$FIXTURE/second.json" >/dev/null
grep -Fx 'plugin marketplace update waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin update waza@waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin marketplace upgrade waza' "$FIXTURE/home/codex-mutations.log" >/dev/null

REMOVE_FIXTURE="$TMP_ROOT/remove"
cp -R "$FIXTURE" "$REMOVE_FIXTURE"
jq '.sources[0].defaultDestinations = ["claude"] | .sources[0].overrides.waza = ["claude"]' \
  "$REMOVE_FIXTURE/skill-topology.json" > "$REMOVE_FIXTURE/manifest.tmp"
mv "$REMOVE_FIXTURE/manifest.tmp" "$REMOVE_FIXTURE/skill-topology.json"
HOME="$REMOVE_FIXTURE/home" TMPDIR="$REMOVE_FIXTURE/runtime" PATH="$REMOVE_FIXTURE/bin:$PATH" \
  "$REMOVE_FIXTURE/scripts/update-skill-topology.sh" --json > "$REMOVE_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  ([.changes[] | {action, destination}] == [{"action":"removed","destination":"codex"}])
' "$REMOVE_FIXTURE/result.json" >/dev/null
jq -e '.installed == []' "$REMOVE_FIXTURE/home/codex-plugins.json" >/dev/null
grep -Fx 'plugin remove waza@waza' "$REMOVE_FIXTURE/home/codex-mutations.log" >/dev/null

UNKNOWN_FIXTURE="$TMP_ROOT/unknown"
cp -R "$FIXTURE" "$UNKNOWN_FIXTURE"
cat > "$UNKNOWN_FIXTURE/home/claude-plugins.json" <<'JSON'
[
  {"id":"waza@waza","version":"1.0.0","enabled":true},
  {"id":"frontend-design@claude-plugins-official","version":"1.0.0","enabled":true},
  {"id":"rogue@custom-market","version":"1.0.0","enabled":true}
]
JSON
cat > "$UNKNOWN_FIXTURE/home/codex-plugins.json" <<'JSON'
{
  "installed": [
    {"pluginId":"waza@waza","marketplaceName":"waza","version":"1.0.0","installed":true,"enabled":true},
    {"pluginId":"documents@openai-primary-runtime","marketplaceName":"openai-primary-runtime","version":"1.0.0","installed":true,"enabled":true},
    {"pluginId":"browser@openai-bundled","marketplaceName":"openai-bundled","version":"1.0.0","installed":true,"enabled":true},
    {"pluginId":"rogue@custom-market","marketplaceName":"custom-market","version":"1.0.0","installed":true,"enabled":true},
    {"pluginId":"rogue-openai@openai-community","marketplaceName":"openai-community","version":"1.0.0","installed":true,"enabled":true}
  ]
}
JSON
cp "$UNKNOWN_FIXTURE/home/claude-mutations.log" "$UNKNOWN_FIXTURE/claude-mutations-before"
cp "$UNKNOWN_FIXTURE/home/codex-mutations.log" "$UNKNOWN_FIXTURE/codex-mutations-before"
set +e
HOME="$UNKNOWN_FIXTURE/home" TMPDIR="$UNKNOWN_FIXTURE/runtime" PATH="$UNKNOWN_FIXTURE/bin:$PATH" \
  "$UNKNOWN_FIXTURE/scripts/update-skill-topology.sh" --json > "$UNKNOWN_FIXTURE/result.json"
unknown_exit=$?
set -e
test "$unknown_exit" -eq 3
if ! jq -e '
  .status == "decision-required" and .changes == [] and
  ([.decisions[] | {code, pluginId, destination}] == [
    {"code":"unknown-installed-plugin","pluginId":"rogue-openai@openai-community","destination":"codex"},
    {"code":"unknown-installed-plugin","pluginId":"rogue@custom-market","destination":"claude"},
    {"code":"unknown-installed-plugin","pluginId":"rogue@custom-market","destination":"codex"}
  ]) and
  ([.decisions[] | select(.pluginId == "frontend-design@claude-plugins-official" or .pluginId == "documents@openai-primary-runtime" or .pluginId == "browser@openai-bundled")] | length) == 0
' "$UNKNOWN_FIXTURE/result.json" >/dev/null; then
  cat "$UNKNOWN_FIXTURE/result.json" >&2
  exit 1
fi
cmp -s "$UNKNOWN_FIXTURE/claude-mutations-before" "$UNKNOWN_FIXTURE/home/claude-mutations.log"
cmp -s "$UNKNOWN_FIXTURE/codex-mutations-before" "$UNKNOWN_FIXTURE/home/codex-mutations.log"

CLAUDE_DISABLED_FIXTURE="$TMP_ROOT/claude-disabled"
cp -R "$FIXTURE" "$CLAUDE_DISABLED_FIXTURE"
jq 'map(if .id == "waza@waza" then .enabled = false else . end)' \
  "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json" > "$CLAUDE_DISABLED_FIXTURE/disabled.tmp"
mv "$CLAUDE_DISABLED_FIXTURE/disabled.tmp" "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json"
HOME="$CLAUDE_DISABLED_FIXTURE/home" TMPDIR="$CLAUDE_DISABLED_FIXTURE/runtime" \
PATH="$CLAUDE_DISABLED_FIXTURE/bin:$PATH" \
  "$CLAUDE_DISABLED_FIXTURE/scripts/update-skill-topology.sh" --json > "$CLAUDE_DISABLED_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  (.changes[] | .action == "installed" and .sourceId == "waza" and .destination == "claude")
' "$CLAUDE_DISABLED_FIXTURE/result.json" >/dev/null
jq -e '.[0].enabled == true' "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json" >/dev/null
grep -Fx 'plugin enable waza@waza' "$CLAUDE_DISABLED_FIXTURE/home/claude-mutations.log" >/dev/null

CODEX_DISABLED_FIXTURE="$TMP_ROOT/codex-disabled"
cp -R "$FIXTURE" "$CODEX_DISABLED_FIXTURE"
jq '.installed |= map(if .pluginId == "waza@waza" then .enabled = false else . end)' \
  "$CODEX_DISABLED_FIXTURE/home/codex-plugins.json" > "$CODEX_DISABLED_FIXTURE/disabled.tmp"
mv "$CODEX_DISABLED_FIXTURE/disabled.tmp" "$CODEX_DISABLED_FIXTURE/home/codex-plugins.json"
set +e
HOME="$CODEX_DISABLED_FIXTURE/home" TMPDIR="$CODEX_DISABLED_FIXTURE/runtime" \
PATH="$CODEX_DISABLED_FIXTURE/bin:$PATH" \
  "$CODEX_DISABLED_FIXTURE/scripts/update-skill-topology.sh" --json > "$CODEX_DISABLED_FIXTURE/result.json"
codex_disabled_exit=$?
set -e
test "$codex_disabled_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("waza@waza is installed but disabled") and contains("Codex config"))
' "$CODEX_DISABLED_FIXTURE/result.json" >/dev/null
jq -e '.installed[0].enabled == false' "$CODEX_DISABLED_FIXTURE/home/codex-plugins.json" >/dev/null

UPDATE_FIXTURE="$TMP_ROOT/update"
cp -R "$FIXTURE" "$UPDATE_FIXTURE"
FAKE_PLUGIN_UPDATE_VERSION=2.0.0 \
HOME="$UPDATE_FIXTURE/home" TMPDIR="$UPDATE_FIXTURE/runtime" PATH="$UPDATE_FIXTURE/bin:$PATH" \
  "$UPDATE_FIXTURE/scripts/update-skill-topology.sh" --json > "$UPDATE_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  ([.changes[] | {action, destination}] == [
    {"action":"updated","destination":"claude"},
    {"action":"updated","destination":"codex"}
  ])
' "$UPDATE_FIXTURE/result.json" >/dev/null
jq -e '.[0].version == "2.0.0"' "$UPDATE_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed[0].version == "2.0.0"' "$UPDATE_FIXTURE/home/codex-plugins.json" >/dev/null

FAILURE_FIXTURE="$TMP_ROOT/failure"
cp -R "$FIXTURE" "$FAILURE_FIXTURE"
printf '{"installed":[]}\n' > "$FAILURE_FIXTURE/home/codex-plugins.json"
set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_CODEX_INSTALL_FAIL=1 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$FAILURE_FIXTURE/home" TMPDIR="$FAILURE_FIXTURE/runtime" PATH="$FAILURE_FIXTURE/bin:$PATH" \
  "$FAILURE_FIXTURE/scripts/update-skill-topology.sh" --json > "$FAILURE_FIXTURE/result.json"
failure_exit=$?
set -e
test "$failure_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("Claude marketplace update failed") and contains("fixture Claude marketplace failure")) and
  any(.errors[]; contains("Codex plugin install failed") and contains("fixture Codex install failure")) and
  any(.errors[]; contains("final verification failed: waza/waza -> codex: missing"))
' "$FAILURE_FIXTURE/result.json" >/dev/null

set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_CODEX_INSTALL_FAIL=1 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$FAILURE_FIXTURE/home" TMPDIR="$FAILURE_FIXTURE/runtime" PATH="$FAILURE_FIXTURE/bin:$PATH" \
  "$FAILURE_FIXTURE/scripts/update-skill-topology.sh" > "$FAILURE_FIXTURE/human.out" 2> "$FAILURE_FIXTURE/human.err"
failure_human_exit=$?
set -e
test "$failure_human_exit" -eq 1
grep -F 'error: source waza reconciliation failed: Claude marketplace update failed' "$FAILURE_FIXTURE/human.err" >/dev/null
grep -F 'error: source waza reconciliation failed: Codex plugin install failed' "$FAILURE_FIXTURE/human.err" >/dev/null
grep -F 'error: final verification failed: waza/waza -> codex: missing' "$FAILURE_FIXTURE/human.err" >/dev/null

jq -e '
  ([.sources[] | select(.id == "waza" or .id == "claude-mem") | {
    id, classification, defaultDestinations, overrides
  }] | length) == 2 and
  all(.sources[] | select(.id == "waza" or .id == "claude-mem");
    .classification == "plugin-both" and .defaultDestinations == ["claude","codex"])
' "$REPO_ROOT/skill-topology.json" >/dev/null

MEM_FIXTURE="$TMP_ROOT/claude-mem"
MEM_BIN="$MEM_FIXTURE/bin"
mkdir -p "$MEM_FIXTURE/scripts" "$MEM_FIXTURE/home/.bun/bin" "$MEM_FIXTURE/home/.local/bin" \
  "$MEM_FIXTURE/home/.claude-mem" "$MEM_FIXTURE/runtime" "$MEM_BIN"
cp "$REPO_ROOT/scripts/update-skill-topology.sh" "$MEM_FIXTURE/scripts/"
cp -R "$REPO_ROOT/scripts/distribution-topology" "$MEM_FIXTURE/scripts/"
jq '{version, sources: [.sources[] | select(.id == "claude-mem")]}' \
  "$REPO_ROOT/skill-topology.json" > "$MEM_FIXTURE/skill-topology.json"
jq '[.[] | select(.sourceId == "claude-mem")]' \
  "$REPO_ROOT/scripts/distribution-topology/registry.json" \
  > "$MEM_FIXTURE/scripts/distribution-topology/registry.json"
printf 'shared database fixture\n' > "$MEM_FIXTURE/home/.claude-mem/database.sqlite"
cp "$MEM_FIXTURE/home/.claude-mem/database.sqlite" "$MEM_FIXTURE/database-before"
printf '[]\n' > "$MEM_FIXTURE/home/claude-plugins.json"
printf '[]\n' > "$MEM_FIXTURE/home/claude-marketplaces.json"
printf '{"installed":[]}\n' > "$MEM_FIXTURE/home/codex-plugins.json"
printf '{"marketplaces":[]}\n' > "$MEM_FIXTURE/home/codex-marketplaces.json"

cat > "$MEM_BIN/dependency" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$0")" >> "$HOME/dependency-calls.log"
printf '1.0.0\n'
BASH
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.bun/bin/bun"
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.local/bin/uv"
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.local/bin/uvx"
chmod +x "$MEM_FIXTURE/home/.bun/bin/bun" "$MEM_FIXTURE/home/.local/bin/uv" \
  "$MEM_FIXTURE/home/.local/bin/uvx"

cat > "$MEM_BIN/claude" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json') cat "$HOME/claude-plugins.json" ;;
  'plugin marketplace list --json') cat "$HOME/claude-marketplaces.json" ;;
  'plugin marketplace add thedotmack/claude-mem')
    printf '[{"name":"thedotmack"}]\n' > "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace update thedotmack') ;;
  'plugin install claude-mem@thedotmack')
    if [ "${FAKE_MEM_NO_STATE:-0}" != 1 ]; then
      printf '[{"id":"claude-mem@thedotmack","version":"1.0.0","enabled":true}]\n' \
        > "$HOME/claude-plugins.json"
    fi
    ;;
  'plugin update claude-mem@thedotmack') ;;
  *)
    printf 'unexpected claude-mem Claude call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$MEM_BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json') cat "$HOME/codex-plugins.json" ;;
  'plugin marketplace list --json') cat "$HOME/codex-marketplaces.json" ;;
  'plugin marketplace add thedotmack/claude-mem')
    printf '{"marketplaces":[{"name":"claude-mem-local"}]}\n' > "$HOME/codex-marketplaces.json"
    ;;
  'plugin marketplace upgrade claude-mem-local') ;;
  'plugin add claude-mem@claude-mem-local')
    if [ "${FAKE_MEM_NO_STATE:-0}" != 1 ]; then
      printf '{"installed":[{"pluginId":"claude-mem@claude-mem-local","marketplaceName":"claude-mem-local","version":"1.0.0","installed":true,"enabled":true}]}\n' \
        > "$HOME/codex-plugins.json"
    fi
    ;;
  *)
    printf 'unexpected claude-mem Codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH
chmod +x "$MEM_BIN/claude" "$MEM_BIN/codex"

MEM_VERIFY_FIXTURE="$TMP_ROOT/claude-mem-verify"
cp -R "$MEM_FIXTURE" "$MEM_VERIFY_FIXTURE"

HOME="$MEM_FIXTURE/home" TMPDIR="$MEM_FIXTURE/runtime" PATH="$MEM_BIN:$PATH" \
  "$MEM_FIXTURE/scripts/update-skill-topology.sh" --json > "$MEM_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  (.plan[] | .sourceId == "claude-mem" and .skill == "claude-mem" and .destinations == ["claude","codex"]) and
  ([.changes[] | select(.action == "installed") | .destination] == ["claude","codex"]) and
  .errors == []
' "$MEM_FIXTURE/result.json" >/dev/null
test "$(sort -u "$MEM_FIXTURE/home/dependency-calls.log")" = "$(printf '%s\n' bun uv uvx | sort)"
cmp -s "$MEM_FIXTURE/database-before" "$MEM_FIXTURE/home/.claude-mem/database.sqlite"

set +e
FAKE_MEM_NO_STATE=1 \
HOME="$MEM_VERIFY_FIXTURE/home" TMPDIR="$MEM_VERIFY_FIXTURE/runtime" PATH="$MEM_VERIFY_FIXTURE/bin:$PATH" \
  "$MEM_VERIFY_FIXTURE/scripts/update-skill-topology.sh" --json > "$MEM_VERIFY_FIXTURE/result.json"
mem_verify_exit=$?
set -e
test "$mem_verify_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("remains missing after install")) and
  any(.errors[]; contains("source claude-mem verification failed")) and
  any(.errors[]; contains("final verification failed: claude-mem/claude-mem"))
' "$MEM_VERIFY_FIXTURE/result.json" >/dev/null
cmp -s "$MEM_VERIFY_FIXTURE/database-before" "$MEM_VERIFY_FIXTURE/home/.claude-mem/database.sqlite"

echo "plugin-distributed topology tests passed"
