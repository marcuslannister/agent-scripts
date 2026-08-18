#!/usr/bin/env bash
set -euo pipefail

# Codex registry repair: report a lost marketplace or plugin record, and
# re-register it through `codex` commands only. Regression for a desynced Codex
# registry making acquire retry a doomed `marketplace add` on every run.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN="$TMP_ROOT/bin"
STATE="$TMP_ROOT/state"
FIXTURE="$TMP_ROOT/repo"
mkdir -p "$BIN" "$STATE" "$FIXTURE/agent-tooling"

# The script reads the sources.json beside it, so it runs from a fixture copy
# with a fixed source list: otherwise adding any Codex plugin source to the real
# sources.json fails this test for a registry that is in fact healthy.
cp "$REPO_ROOT/agent-tooling/repair-codex-registry.sh" "$FIXTURE/agent-tooling/"
cat > "$FIXTURE/agent-tooling/sources.json" <<'JSON'
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
        "marketplaces": { "claude": "thedotmack", "codex": "claude-mem-local" }
      }
    }
  ]
}
JSON

COMMAND="$FIXTURE/agent-tooling/repair-codex-registry.sh"

# Fake Codex: marketplaces and installed plugins are one name per line, and the
# stale-root defect is modelled as an add that refuses until a remove clears it.
cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
markets="$CODEX_STATE/marketplaces"
plugins="$CODEX_STATE/plugins"
roots="$CODEX_STATE/roots"
log="$CODEX_STATE/calls.log"
touch "$markets" "$plugins" "$roots"
printf '%s\n' "$*" >> "$log"
case "$*" in
  'plugin marketplace list --json')
    jq -Rn --rawfile names "$markets" \
      '{marketplaces: ($names | split("\n") | map(select(length > 0) | {name: ., root: "/tmp"}))}'
    ;;
  'plugin list --json')
    jq -Rn --rawfile names "$plugins" \
      '{installed: ($names | split("\n") | map(select(length > 0) | {pluginId: ., installed: true, enabled: true})), available: []}'
    ;;
  'plugin marketplace remove '*)
    name="${*: -1}"
    grep -Fxv "$name" "$markets" > "$markets.tmp" || true
    mv "$markets.tmp" "$markets"
    grep -Fxv "$name" "$roots" > "$roots.tmp" || true
    mv "$roots.tmp" "$roots"
    printf 'Removed marketplace `%s`.\n' "$name"
    ;;
  'plugin marketplace add '*)
    repo="${*: -1}"
    name="$(jq -r --arg repo "$repo" '.[$repo] // ""' "$CODEX_STATE/repo-map.json")"
    if [ -z "$name" ]; then
      printf 'Error: no marketplace for source %s\n' "$repo" >&2
      exit 1
    fi
    if grep -Fxq "$name" "$roots"; then
      printf "Error: marketplace '%s' is already added from a different source\n" "$name" >&2
      exit 1
    fi
    printf '%s\n' "$name" >> "$markets"
    printf '%s\n' "$name" >> "$roots"
    printf 'Added marketplace `%s` from %s.\n' "$name" "$repo"
    ;;
  'plugin add '*)
    printf '%s\n' "${*: -1}" >> "$plugins"
    printf 'Added plugin `%s`.\n' "${*: -1}"
    ;;
  *)
    printf 'unexpected codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH
chmod +x "$BIN/codex"

cat > "$STATE/repo-map.json" <<'JSON'
{"tw93/Waza":"waza","thedotmack/claude-mem":"claude-mem-local"}
JSON

run() { # extra-args...
  CODEX_STATE="$STATE" PATH="$BIN:$PATH" "$COMMAND" "$@"
}

# Healthy registry: report only, no mutation, exit 0.
printf '%s\n' waza claude-mem-local > "$STATE/marketplaces"
cp "$STATE/marketplaces" "$STATE/roots"
printf '%s\n' waza@waza claude-mem@claude-mem-local > "$STATE/plugins"
: > "$STATE/calls.log"
run > "$TMP_ROOT/healthy.out"
grep -q 'matches every expected marketplace and plugin' "$TMP_ROOT/healthy.out"
grep -Eq 'marketplace (add|remove)|plugin add' "$STATE/calls.log" \
  && { echo "report mutated a healthy registry" >&2; exit 1; }

# Desynced registry: the roots survive, so a plain add would refuse.
printf '%s\n' waza > "$STATE/marketplaces"
printf '%s\n' waza claude-mem-local > "$STATE/roots"
printf '%s\n' waza@waza > "$STATE/plugins"
: > "$STATE/calls.log"
set +e
run > "$TMP_ROOT/report.out" 2> "$TMP_ROOT/report.err"
report_exit=$?
set -e
test "$report_exit" -eq 1
grep -q 'claude-mem' "$TMP_ROOT/report.out"
grep -q '1 Codex entry desynced' "$TMP_ROOT/report.err"
grep -Eq 'marketplace (add|remove)|plugin add' "$STATE/calls.log" \
  && { echo "report mutated a desynced registry" >&2; exit 1; }

# --fix removes the stale root first, then re-adds and installs.
: > "$STATE/calls.log"
run --fix > "$TMP_ROOT/fix.out"
grep -Fxq claude-mem-local "$STATE/marketplaces"
grep -Fxq claude-mem@claude-mem-local "$STATE/plugins"
grep -Fxq 'plugin marketplace remove claude-mem-local' "$STATE/calls.log"
grep -Fxq 'plugin marketplace add thedotmack/claude-mem' "$STATE/calls.log"
grep -Fxq 'plugin add claude-mem@claude-mem-local' "$STATE/calls.log"
# The healthy source is left alone.
grep -Fxq 'plugin marketplace remove waza' "$STATE/calls.log" \
  && { echo "--fix touched a healthy source" >&2; exit 1; }

# Repair is idempotent: a second run reports clean.
run > "$TMP_ROOT/second.out"
grep -q 'matches every expected marketplace and plugin' "$TMP_ROOT/second.out"

# A registered marketplace with a missing plugin installs the plugin only. Re-adding
# it would discard a snapshot that costs a full clone — 25 minutes for claude-mem.
printf '%s\n' waza claude-mem-local > "$STATE/marketplaces"
cp "$STATE/marketplaces" "$STATE/roots"
printf '%s\n' waza@waza > "$STATE/plugins"
: > "$STATE/calls.log"
run --fix > "$TMP_ROOT/plugin-only.out"
grep -Fxq claude-mem@claude-mem-local "$STATE/plugins"
grep -Fxq 'plugin add claude-mem@claude-mem-local' "$STATE/calls.log"
grep -Eq 'plugin marketplace (add|remove)' "$STATE/calls.log" \
  && { echo "--fix re-added a registered marketplace" >&2; exit 1; }

# A failing add is reported, not swallowed.
printf '%s\n' waza > "$STATE/marketplaces"
printf '%s\n' waza claude-mem-local > "$STATE/roots"
printf '%s\n' waza@waza > "$STATE/plugins"
rm -f "$STATE/repo-map.json"
printf '{"tw93/Waza":"waza"}\n' > "$STATE/repo-map.json"
set +e
run --fix > "$TMP_ROOT/fail.out" 2> "$TMP_ROOT/fail.err"
fix_exit=$?
set -e
test "$fix_exit" -eq 1
grep -q 'repairs failed' "$TMP_ROOT/fail.err"

echo "repair-codex-registry tests passed"
