#!/usr/bin/env bash
set -euo pipefail

# --plugins-only contract: reconcile native plugins on a secondary machine while
# leaving every staging-bearing source untouched. Regression for update-local.sh
# never refreshing plugins, which froze mattpocock-skills at 1.2.0 indefinitely.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
export REAL_GIT
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/plugins-only"
UPSTREAM="$TMP_ROOT/upstreams/anthropic-skills"
BIN="$FIXTURE/bin"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/other-skills/anthropics" "$FIXTURE/runtime" \
  "$FIXTURE/home/.claude/skills" "$FIXTURE/home/.agents/skills" "$FIXTURE/home/.codex" \
  "$FIXTURE/home/plugin-roots/claude/waza/skills/think" \
  "$FIXTURE/remote-marketplace/.claude-plugin" \
  "$UPSTREAM/skills" "$BIN"

cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

ANTHROPIC_SKILLS=(docx pdf)
for skill in "${ANTHROPIC_SKILLS[@]}"; do
  mkdir -p "$UPSTREAM/skills/$skill"
  printf '%s\n' '---' "name: $skill" 'description: "upstream fixture"' '---' \
    > "$UPSTREAM/skills/$skill/SKILL.md"
done
mkdir -p "$UPSTREAM/.git"

printf 'claude-skills\n' > "$FIXTURE/home/.claude/skills/.agent-scripts-root"
printf '# Waza think\n' > "$FIXTURE/home/plugin-roots/claude/waza/skills/think/SKILL.md"

cat > "$FIXTURE/agent-tooling/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "anthropic-skills",
      "classification": "source-only",
      "defaultDestinations": ["claude", "codex"]
    },
    {
      "id": "waza",
      "classification": "plugin-claude-only",
      "defaultDestinations": ["claude"]
    }
  ]
}
JSON

cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "anthropic-skills",
    "classification": "source-only",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/copy-source.sh",
    "stateInspection": "adapter",
    "matrixSource": "anthropics/skills"
  },
  {
    "sourceId": "waza",
    "classification": "plugin-claude-only",
    "supportedDestinations": ["claude"],
    "command": "adapters/plugin-both.sh",
    "stateInspection": "adapter",
    "matrixSource": "tw93/Waza",
    "plugin": {
      "name": "waza",
      "repo": "tw93/Waza",
      "marketplaces": {"claude": "waza"},
      "skills": ["waza"]
    }
  }
]
JSON

cat > "$FIXTURE/remote-marketplace/.claude-plugin/marketplace.json" <<'JSON'
{"name":"waza","plugins":[{"name":"waza","version":"1.0.0","source":"./plugins/waza"}]}
JSON

# Plugin starts absent so a --plugins-only run must install it.
printf '[]\n' > "$FIXTURE/home/claude-plugins.json"
printf '[{"name":"waza"}]\n' > "$FIXTURE/home/claude-marketplaces.json"

cat > "$BIN/claude" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    jq --arg path "$HOME/plugin-roots/claude/waza" '
      map(if .id == "waza@waza" then .installPath = $path else . end)
    ' "$HOME/claude-plugins.json"
    ;;
  'plugin marketplace list --json')
    jq --arg root "$HOME/claude-marketplace" 'map(. + {installLocation:$root})' \
      "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace update waza')
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin install waza@waza')
    jq -n --arg path "$HOME/plugin-roots/claude/waza" \
      '[{id:"waza@waza",version:"1.0.0",enabled:true,installPath:$path}]' \
      > "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin update waza@waza'|'plugin enable waza@waza')
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  *)
    printf 'unexpected claude call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  mkdir -p "$(dirname "$destination")"
  case "$*" in
    *tw93/Waza*)     cp -R "$FAKE_WAZA_MARKETPLACE" "$destination" ;;
    *anthropics/skills*) cp -R "$FAKE_ANTHROPIC_UPSTREAM" "$destination" ;;
    *) printf 'unexpected clone: %s\n' "$*" >&2; exit 1 ;;
  esac
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = pull ]; then
  printf 'Already up to date.\n'
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = rev-parse ]; then
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
  exit 0
fi
exec "$REAL_GIT" "$@"
BASH
chmod +x "$BIN/claude" "$BIN/git"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add agent-tooling other-skills 2>/dev/null || true

COMMAND="$FIXTURE/agent-tooling/update-skill-topology.sh"
export FAKE_ANTHROPIC_UPSTREAM="$UPSTREAM"
export FAKE_WAZA_MARKETPLACE="$FIXTURE/remote-marketplace"

run_acquire() { # output-json extra-args...
  local output="$1"; shift
  HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
    "$COMMAND" --json "$@" > "$output"
}

# --plugins-only --check previews the plugin source and nothing else.
run_acquire "$FIXTURE/check.json" --plugins-only --check || true
if ! jq -e '
  (.errors | length) == 0 and
  (all(.sources[]; .id == "waza")) and
  (all(.plan[]; .sourceId == "waza"))
' "$FIXTURE/check.json" >/dev/null; then
  cat "$FIXTURE/check.json" >&2
  echo "plugins-only check leaked a staging-bearing source" >&2
  exit 1
fi
[ ! -e "$FIXTURE/other-skills/anthropics/docx" ]
[ ! -e "$FIXTURE/other-skills/anthropics/.source.json" ]

# --plugins-only reconcile installs the plugin and writes no staging.
run_acquire "$FIXTURE/plugins-only.json" --plugins-only
if ! jq -e '
  (.errors | length) == 0 and
  (all(.sources[]; .id == "waza")) and
  (all(.plan[]; .sourceId == "waza")) and
  (all(.changes[]; .destination != "staging"))
' "$FIXTURE/plugins-only.json" >/dev/null; then
  cat "$FIXTURE/plugins-only.json" >&2
  echo "plugins-only reconcile touched staging" >&2
  exit 1
fi
# The plugin really was reconciled — this is the frozen-plugin regression.
grep -Fq 'plugin install waza@waza' "$FIXTURE/home/claude-mutations.log"
# Reconcile keeps the marketplace clone in the machine-local cache, so later runs
# refresh one clone instead of paying a cold clone per source.
test -d "$FIXTURE/home/.cache/agent-scripts/source-clones/waza"
jq -e 'any(.[]; .id == "waza@waza")' "$FIXTURE/home/claude-plugins.json" >/dev/null
# Staging stayed git-owned: no mirror, no .source.json rewrite.
for skill in "${ANTHROPIC_SKILLS[@]}"; do
  [ ! -e "$FIXTURE/other-skills/anthropics/$skill" ]
done
[ ! -e "$FIXTURE/other-skills/anthropics/.source.json" ]

# Control: a full acquire on the same fixture does stage, proving the flag gates it.
run_acquire "$FIXTURE/full.json"
jq -e 'any(.sources[]; .id == "anthropic-skills")' "$FIXTURE/full.json" >/dev/null
for skill in "${ANTHROPIC_SKILLS[@]}"; do
  test -f "$FIXTURE/other-skills/anthropics/$skill/SKILL.md"
done
test -f "$FIXTURE/other-skills/anthropics/.source.json"

# --plugins-only is idempotent once the plugin is current.
run_acquire "$FIXTURE/second.json" --plugins-only
jq -e '(.errors | length) == 0 and (.changes | length) == 0' \
  "$FIXTURE/second.json" >/dev/null

echo "update-skill-topology --plugins-only tests passed"
