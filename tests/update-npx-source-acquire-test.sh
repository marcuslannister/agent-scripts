#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
UPSTREAM="$TMP_ROOT/upstream"
BIN="$TMP_ROOT/bin"
mkdir -p \
  "$FIXTURE/agent-tooling" \
  "$FIXTURE/other-skills/matt" \
  "$FIXTURE/home/.agents/skills/preexisting" \
  "$FIXTURE/home/.claude/skills/preexisting" \
  "$FIXTURE/runtime" \
  "$UPSTREAM/skills/engineering" \
  "$BIN"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

for skill in alpha code-review new-skill; do
  mkdir -p "$UPSTREAM/skills/engineering/$skill"
  printf '%s\n' '---' "name: $skill" 'description: fixture' '---' \
    > "$UPSTREAM/skills/engineering/$skill/SKILL.md"
done
printf '%s\n' keep > "$FIXTURE/home/.agents/skills/preexisting/keep.txt"
printf '%s\n' keep > "$FIXTURE/home/.claude/skills/preexisting/keep.txt"
printf '%s\n' '{"version":3,"skills":{}}' > "$FIXTURE/home/.agents/.skill-lock.json"

cat > "$FIXTURE/agent-tooling/skill-topology.json" <<'JSON'
{"version":1,"sources":[{"id":"matt-skills","classification":"npx-only","defaultDestinations":["codex"]}]}
JSON
cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[{"sourceId":"matt-skills","classification":"npx-only","supportedDestinations":["codex"],"command":"adapters/npx-source.sh","stateInspection":"adapter","matrixSource":"mattpocock/skills"}]
JSON
cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  cp -R "$FAKE_MATT_UPSTREAM" "$destination"
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = rev-parse ] && [ "${4:-}" = HEAD ]; then
  printf 'cccccccccccccccccccccccccccccccccccccccc\n'
  exit 0
fi
exec "$REAL_GIT" "$@"
BASH
cat > "$BIN/npx" <<'BASH'
#!/usr/bin/env bash
printf 'npx must not be called by acquire\n' >&2
exit 97
BASH
chmod +x "$BIN/git" "$BIN/npx"

cp -R "$FIXTURE/home/.agents/skills" "$TMP_ROOT/codex-before"
cp -R "$FIXTURE/home/.claude/skills" "$TMP_ROOT/claude-before"
REAL_GIT="$REAL_GIT" FAKE_MATT_UPSTREAM="$UPSTREAM" \
  HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$FIXTURE/result.json"

jq -e '
  .status == "reconciled" and .errors == [] and
  all(.plan[]; .destinations == []) and
  ([.changes[] | select(.destination == "staging" and .action == "installed")] | length) == 3
' "$FIXTURE/result.json" >/dev/null
for skill in alpha code-review new-skill; do
  test -f "$FIXTURE/other-skills/matt/$skill/SKILL.md"
  test ! -e "$FIXTURE/other-skills/matt/$skill/.agent-scripts-copy"
done
jq -e '.repo == "mattpocock/skills" and .commit == "cccccccccccccccccccccccccccccccccccccccc"' \
  "$FIXTURE/other-skills/matt/.source.json" >/dev/null
diff -r "$TMP_ROOT/codex-before" "$FIXTURE/home/.agents/skills" >/dev/null
diff -r "$TMP_ROOT/claude-before" "$FIXTURE/home/.claude/skills" >/dev/null

echo "npx source acquire tests passed"
