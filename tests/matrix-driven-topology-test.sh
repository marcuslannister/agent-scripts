#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
UPSTREAM="$TMP_ROOT/anthropic-skills"
BIN="$TMP_ROOT/bin"
mkdir -p \
  "$FIXTURE/agent-tooling" \
  "$FIXTURE/skills/repo-remove" \
  "$FIXTURE/skills/repo-same" \
  "$FIXTURE/skills/repo-install" \
  "$FIXTURE/other-skills/anthropics" \
  "$FIXTURE/home/.agents/skills" \
  "$FIXTURE/home/.claude/skills" \
  "$FIXTURE/home/.claude/plugins/cache/test-market/test-plugin/1.0.0" \
  "$FIXTURE/runtime" \
  "$UPSTREAM/skills/foreign-remove" \
  "$UPSTREAM/skills/foreign-same" \
  "$UPSTREAM/skills/foreign-install" \
  "$UPSTREAM/.git" \
  "$BIN"

cp "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" \
  "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

for skill in repo-remove repo-same repo-install; do
  printf '%s\n' '---' "name: $skill" 'description: "fixture"' '---' \
    > "$FIXTURE/skills/$skill/SKILL.md"
done
for skill in foreign-remove foreign-same foreign-install; do
  printf '%s\n' '---' "name: $skill" 'description: "fixture"' '---' \
    > "$UPSTREAM/skills/$skill/SKILL.md"
  mkdir -p "$FIXTURE/other-skills/anthropics/$skill"
  cp "$UPSTREAM/skills/$skill/SKILL.md" "$FIXTURE/other-skills/anthropics/$skill/SKILL.md"
done
printf '%s\n' '{"repo":"anthropics/skills","commit":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","syncedAt":"2026-07-25T00:00:00Z"}' \
  > "$FIXTURE/other-skills/anthropics/.source.json"
printf '%s\n' '---' 'name: test-plugin' 'description: "fixture"' '---' \
  > "$FIXTURE/home/.claude/plugins/cache/test-market/test-plugin/1.0.0/SKILL.md"
printf '%s\n' '{"test-market":{"source":{"repo":"https://github.com/example/test-plugin.git"}}}' \
  > "$FIXTURE/home/.claude/plugins/known_marketplaces.json"
printf 'claude-skills\n' > "$FIXTURE/home/.claude/skills/.agent-scripts-root"

cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  mkdir -p "$(dirname "$destination")"
  cp -R "$FAKE_ANTHROPIC_UPSTREAM" "$destination"
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = pull ] && [ "${4:-}" = --ff-only ]; then
  exit 0
fi
exec "$REAL_GIT" "$@"
BASH
chmod +x "$BIN/git"

cat > "$FIXTURE/agent-tooling/distribution-topology/adapters/test-plugin.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
action="${4:-discover}"
plan_path="${5:-}"
case "$action" in
  discover) printf 'test-plugin\n' ;;
  inspect)
    while IFS=$'\t' read -r expected skill destination; do
      case "$expected:$destination" in
        present:claude) printf 'present\t%s\t%s\tok\n' "$skill" "$destination" ;;
        *) printf 'absent\t%s\t%s\tmissing\n' "$skill" "$destination" ;;
      esac
    done < "$plan_path"
    ;;
  reconcile|verify) ;;
esac
BASH
chmod +x "$FIXTURE/agent-tooling/distribution-topology/adapters/test-plugin.sh"

cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "repo-claude",
    "classification": "repo-owned",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/repo-owned.sh",
    "matrixSource": "steipete/agent-scripts"
  },
  {
    "sourceId": "anthropic-skills",
    "classification": "source-only",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/copy-source.sh",
    "stateInspection": "adapter",
    "matrixSource": "anthropics/skills"
  },
  {
    "sourceId": "test-plugin",
    "classification": "plugin-claude-only",
    "supportedDestinations": ["claude"],
    "command": "adapters/test-plugin.sh",
    "stateInspection": "adapter",
    "plugin": {
      "name": "test-plugin",
      "repo": "example/test-plugin",
      "marketplaces": {"claude": "test-market"},
      "skills": ["test-plugin"]
    }
  }
]
JSON

cat > "$FIXTURE/agent-tooling/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {
        "repo-remove": ["claude", "codex"],
        "repo-same": ["claude", "codex"]
      }
    },
    {
      "id": "anthropic-skills",
      "classification": "source-only",
      "defaultDestinations": ["claude", "codex"],
      "overrides": {"foreign-install": ["claude"]}
    },
    {
      "id": "test-plugin",
      "classification": "plugin-claude-only",
      "defaultDestinations": ["claude"],
      "overrides": {}
    }
  ]
}
JSON

cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
# Skills matrix

| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `foreign-install` | anthropics/skills | skill | Y | N | ~1 |
| `foreign-remove` | anthropics/skills | skill | Y | Y | ~1 |
| `foreign-same` | anthropics/skills | skill | Y | Y | ~1 |
| `repo-install` | steipete/agent-scripts | skill | Y | N | ~1 |
| `repo-remove` | steipete/agent-scripts | skill | Y | Y | ~1 |
| `repo-same` | steipete/agent-scripts | skill | Y | Y | ~1 |
| `test-plugin` | example/test-plugin | plugin | Y | N | ~1 |
MARKDOWN

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add skills other-skills

run_topology() {
  FAKE_ANTHROPIC_UPSTREAM="$UPSTREAM" REAL_GIT="$REAL_GIT" \
    HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
    "$FIXTURE/agent-tooling/sync-skill-surfaces.sh" "$@"
}

replace_row() {
  local skill="$1" replacement="$2" temporary="$FIXTURE/agent-tooling/skills-matrix.tmp"
  awk -v skill="| \`$skill\` |" -v replacement="$replacement" \
    'index($0, skill) == 1 { print replacement; next } { print }' \
    "$FIXTURE/agent-tooling/skills-matrix.md" > "$temporary"
  mv "$temporary" "$FIXTURE/agent-tooling/skills-matrix.md"
}

run_topology --json > "$FIXTURE/baseline.json"
jq -e '.status == "reconciled" and .errors == [] and .decisions == []' "$FIXTURE/baseline.json" >/dev/null
rg -F '## Counts' "$FIXTURE/agent-tooling/skills-matrix.md" >/dev/null

replace_row repo-remove '| `repo-remove` | steipete/agent-scripts | skill | Y | N | ~1 |'
replace_row repo-install '| `repo-install` | steipete/agent-scripts | skill | Y | Y | ~1 |'
replace_row foreign-remove '| `foreign-remove` | anthropics/skills | skill | Y | N | ~1 |'
replace_row foreign-install '| `foreign-install` | anthropics/skills | skill | Y | Y | ~1 |'
printf '\nSTALE MATRIX SENTINEL\n' >> "$FIXTURE/agent-tooling/skills-matrix.md"

manifest_before_check="$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")"
matrix_before_check="$(shasum -a 256 "$FIXTURE/agent-tooling/skills-matrix.md")"
set +e
run_topology --check --json > "$FIXTURE/check.json"
check_exit=$?
set -e
test "$check_exit" -eq 1
test "$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")" = "$manifest_before_check"
test "$(shasum -a 256 "$FIXTURE/agent-tooling/skills-matrix.md")" = "$matrix_before_check"
rg -F 'STALE MATRIX SENTINEL' "$FIXTURE/agent-tooling/skills-matrix.md" >/dev/null
jq -e '
  (.plan[] | select(.skill == "repo-remove") | .destinations == ["claude"]) and
  (.plan[] | select(.skill == "repo-same") | .destinations == ["claude", "codex"]) and
  (.plan[] | select(.skill == "repo-install") | .destinations == ["claude", "codex"]) and
  (.plan[] | select(.skill == "foreign-remove") | .destinations == ["claude"]) and
  (.plan[] | select(.skill == "foreign-same") | .destinations == ["claude", "codex"]) and
  (.plan[] | select(.skill == "foreign-install") | .destinations == ["claude", "codex"])
' "$FIXTURE/check.json" >/dev/null
test -d "$FIXTURE/home/.agents/skills/repo-remove"
test ! -e "$FIXTURE/home/.agents/skills/repo-install"
test -d "$FIXTURE/home/.agents/skills/foreign-remove"
test ! -e "$FIXTURE/home/.agents/skills/foreign-install"

run_topology --json > "$FIXTURE/reconciled.json"
jq -e '.status == "reconciled" and .errors == [] and .decisions == []' "$FIXTURE/reconciled.json" >/dev/null
if rg -F 'STALE MATRIX SENTINEL' "$FIXTURE/agent-tooling/skills-matrix.md" >/dev/null; then
  echo 'successful reconcile did not regenerate skills matrix' >&2
  exit 1
fi
rg '^| `repo-remove` | steipete/agent-scripts | skill | Y | N | ~[0-9][0-9]* |$' "$FIXTURE/agent-tooling/skills-matrix.md" >/dev/null
rg '^| `repo-install` | steipete/agent-scripts | skill | Y | Y | ~[0-9][0-9]* |$' "$FIXTURE/agent-tooling/skills-matrix.md" >/dev/null
test ! -e "$FIXTURE/home/.agents/skills/repo-remove"
test -d "$FIXTURE/home/.agents/skills/repo-same"
test -d "$FIXTURE/home/.agents/skills/repo-install"
test ! -e "$FIXTURE/home/.agents/skills/foreign-remove"
test -d "$FIXTURE/home/.agents/skills/foreign-same"
test -d "$FIXTURE/home/.agents/skills/foreign-install"
jq -e '
  all(.sources[] | select(.id == "repo-claude" or .id == "anthropic-skills");
    .matrixOverridesStart == "generated from agent-tooling/skills-matrix.md" and
    .matrixOverridesEnd == "end generated overrides") and
  (.sources[] | select(.id == "repo-claude") | .overrides == {
    "repo-install":["claude","codex"],
    "repo-remove":["claude"],
    "repo-same":["claude","codex"]
  }) and
  (.sources[] | select(.id == "anthropic-skills") | .overrides == {
    "foreign-install":["claude","codex"],
    "foreign-remove":["claude"],
    "foreign-same":["claude","codex"]
  })
' "$FIXTURE/agent-tooling/skill-topology.json" >/dev/null

mv "$FIXTURE/agent-tooling/skills-matrix.md" "$FIXTURE/agent-tooling/skills-matrix.missing"
set +e
run_topology --check --json > "$FIXTURE/missing-matrix.json"
missing_matrix_exit=$?
set -e
test "$missing_matrix_exit" -eq 1
jq -e '.status == "failed" and any(.errors[]; contains("skills matrix is missing"))' \
  "$FIXTURE/missing-matrix.json" >/dev/null
mv "$FIXTURE/agent-tooling/skills-matrix.missing" "$FIXTURE/agent-tooling/skills-matrix.md"

mkdir -p "$UPSTREAM/skills/foreign-new" "$FIXTURE/other-skills/anthropics/foreign-new"
printf '%s\n' '---' 'name: foreign-new' 'description: "fixture"' '---' \
  > "$UPSTREAM/skills/foreign-new/SKILL.md"
cp "$UPSTREAM/skills/foreign-new/SKILL.md" "$FIXTURE/other-skills/anthropics/foreign-new/SKILL.md"
awk '
  /^\| `test-plugin` \|/ { print "| `foreign-removed` | anthropics/skills | skill | N | N | ~1 |" }
  { print }
' "$FIXTURE/agent-tooling/skills-matrix.md" > "$FIXTURE/agent-tooling/skills-matrix.tmp"
mv "$FIXTURE/agent-tooling/skills-matrix.tmp" "$FIXTURE/agent-tooling/skills-matrix.md"
replace_row test-plugin '| `test-plugin` | example/test-plugin | plugin | Y | Y | ~1 |'
cp -R "$FIXTURE/home" "$FIXTURE/home-before-block"
manifest_before_block="$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")"

for mode in check reconcile; do
  args=(--json)
  [ "$mode" = check ] && args=(--check --json)
  set +e
  run_topology "${args[@]}" > "$FIXTURE/$mode-blocked.json"
  blocked_exit=$?
  set -e
  test "$blocked_exit" -eq 3
  jq -e '
    .status == "decision-required" and
    any(.decisions[]; .code == "new-skill" and .skill == "foreign-new") and
    any(.decisions[]; .code == "removed-skill" and .skill == "foreign-removed") and
    any(.decisions[]; .code == "plugin-row-edit" and .skill == "test-plugin")
  ' "$FIXTURE/$mode-blocked.json" >/dev/null
  test "$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")" = "$manifest_before_block"
  diff -r "$FIXTURE/home-before-block" "$FIXTURE/home"
  # Distribute inventory is staging; foreign-new stays staged while decisions block mutation.
  test -f "$FIXTURE/other-skills/anthropics/foreign-new/SKILL.md"
done

replace_row test-plugin '| `test-plugin` | example/test-plugin | plugin | Y | X | ~1 |'
set +e
run_topology --check --json > "$FIXTURE/invalid-plugin-cell.json"
invalid_plugin_exit=$?
set -e
test "$invalid_plugin_exit" -eq 3
jq -e 'any(.decisions[]; .code == "plugin-row-edit" and .skill == "test-plugin")' \
  "$FIXTURE/invalid-plugin-cell.json" >/dev/null

mv "$FIXTURE/home/.claude/plugins/cache/test-market/test-plugin/1.0.0" \
  "$FIXTURE/plugin-cache-absent"
replace_row test-plugin '| `test-plugin` | example/test-plugin | plugin | Y | Y | ~1 |'
set +e
run_topology --check --json > "$FIXTURE/absent-plugin.json"
absent_plugin_exit=$?
set -e
test "$absent_plugin_exit" -eq 3
jq -e 'any(.decisions[]; .code == "plugin-row-edit" and .skill == "test-plugin")' \
  "$FIXTURE/absent-plugin.json" >/dev/null

echo "matrix-driven topology tests passed"
