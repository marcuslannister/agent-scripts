#!/usr/bin/env bash
set -euo pipefail

# Acquire contract: network phase mutates only tracked staging (+ native plugins);
# never matrix/overrides/surfaces/git; --check is zero-write; idempotent.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
export REAL_GIT
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/acquire"
UPSTREAM="$TMP_ROOT/upstreams/anthropic-skills"
BIN="$TMP_ROOT/bin"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/skills" "$FIXTURE/other-skills/anthropics" \
  "$FIXTURE/home/.agents/skills" "$FIXTURE/home/.claude/skills" "$FIXTURE/runtime" \
  "$UPSTREAM/skills" "$BIN"

cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" \
  "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

ANTHROPIC_SKILLS=(docx pdf pptx skill-creator xlsx)
for skill in "${ANTHROPIC_SKILLS[@]}"; do
  mkdir -p "$UPSTREAM/skills/$skill"
  printf '%s\n' '---' "name: $skill" 'description: "upstream fixture"' '---' \
    > "$UPSTREAM/skills/$skill/SKILL.md"
done
mkdir -p "$UPSTREAM/.git"

# Pre-existing surface copies must stay byte-identical through acquire.
mkdir -p "$FIXTURE/home/.claude/skills/docx" "$FIXTURE/home/.agents/skills/docx"
printf '%s\n' '---' 'name: docx' 'description: "preexisting surface"' '---' \
  > "$FIXTURE/home/.claude/skills/docx/SKILL.md"
cp "$FIXTURE/home/.claude/skills/docx/SKILL.md" "$FIXTURE/home/.agents/skills/docx/SKILL.md"
printf '%s\n%s\n%s\n' "$FIXTURE/other-skills/anthropics/docx" anthropic-skills deadbeef \
  > "$FIXTURE/home/.claude/skills/docx/.agent-scripts-copy"
cp "$FIXTURE/home/.claude/skills/docx/.agent-scripts-copy" \
  "$FIXTURE/home/.agents/skills/docx/.agent-scripts-copy"
mkdir -p "$FIXTURE/home/.agents/skills/retired-surface"
printf '%s\n' '---' 'name: retired-surface' 'description: "surface-only fixture"' '---' \
  > "$FIXTURE/home/.agents/skills/retired-surface/SKILL.md"
printf '%s\n%s\n' "$FIXTURE/skills/retired-surface" repo-skills \
  > "$FIXTURE/home/.agents/skills/retired-surface/.agent-scripts-copy"
printf 'claude-skills\n' > "$FIXTURE/home/.claude/skills/.agent-scripts-root"

# Matrix that would select a subset — acquire must ignore it.
cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MD'
# Skills Matrix

| Skill | Source | Type | Claude | Codex |
| --- | --- | --- | --- | --- |
| `docx` | anthropics/skills | skill | Y | N |
| `pdf` | anthropics/skills | skill | N | N |
MD

cat > "$FIXTURE/agent-tooling/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {}
    },
    {
      "id": "anthropic-skills",
      "classification": "source-only",
      "defaultDestinations": ["claude", "codex"],
      "overrides": {
        "docx": ["claude"],
        "pdf": []
      }
    }
  ]
}
JSON

cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "repo-claude",
    "classification": "repo-owned",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/repo-owned.sh"
  },
  {
    "sourceId": "anthropic-skills",
    "classification": "source-only",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/copy-source.sh",
    "stateInspection": "adapter",
    "matrixSource": "anthropics/skills"
  }
]
JSON

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
  printf 'Already up to date.\n'
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = rev-parse ] && [ "${4:-}" = HEAD ]; then
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
  exit 0
fi
exec "$REAL_GIT" "$@"
BASH
chmod +x "$BIN/git"

# Snapshot surfaces + matrix + manifest before acquire.
SURFACE_BEFORE="$TMP_ROOT/surfaces-before"
mkdir -p "$SURFACE_BEFORE"
cp -R "$FIXTURE/home/.claude/skills" "$SURFACE_BEFORE/claude"
cp -R "$FIXTURE/home/.agents/skills" "$SURFACE_BEFORE/codex"
cp "$FIXTURE/agent-tooling/skill-topology.json" "$TMP_ROOT/manifest-before.json"
cp "$FIXTURE/agent-tooling/skills-matrix.md" "$TMP_ROOT/matrix-before.md"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add agent-tooling skills other-skills 2>/dev/null || true

COMMAND="$FIXTURE/agent-tooling/update-skill-topology.sh"
export FAKE_ANTHROPIC_UPSTREAM="$UPSTREAM"

# --check: preview only, zero writes
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --check --json > "$FIXTURE/check.json" || true
jq -e '(.status == "drift" or .status == "clean") and (.errors | length) == 0' \
  "$FIXTURE/check.json" >/dev/null
jq -e 'all(.drift[]; .destination != "claude" and .destination != "codex")' \
  "$FIXTURE/check.json" >/dev/null
diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null
diff -qr "$SURFACE_BEFORE/codex" "$FIXTURE/home/.agents/skills" >/dev/null
cmp "$TMP_ROOT/manifest-before.json" "$FIXTURE/agent-tooling/skill-topology.json"
cmp "$TMP_ROOT/matrix-before.md" "$FIXTURE/agent-tooling/skills-matrix.md"
# check must not stage
[ ! -e "$FIXTURE/other-skills/anthropics/docx/SKILL.md" ]

# Acquire reconcile: stages complete inventory, leaves surfaces/matrix/manifest alone
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/first.json"
jq -e '
  (.status == "reconciled" or .status == "changed" or .status == "clean") and
  (.errors | length) == 0 and
  all(.plan[] | select(.sourceId == "anthropic-skills"); .destinations == []) and
  any(.changes[]; .action == "installed" and .destination == "staging" and .skill == "docx") and
  any(.changes[]; .action == "installed" and .destination == "staging" and .skill == "pdf") and
  any(.changes[]; .action == "installed" and .destination == "staging" and .skill == "pptx") and
  ([.changes[] | select(.destination == "claude" or .destination == "codex")] | length) == 0
' "$FIXTURE/first.json" >/dev/null

for skill in "${ANTHROPIC_SKILLS[@]}"; do
  test -f "$FIXTURE/other-skills/anthropics/$skill/SKILL.md"
done
test -f "$FIXTURE/other-skills/anthropics/.source.json"
jq -e '
  .repo == "https://github.com/anthropics/skills.git" and
  .commit == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
' "$FIXTURE/other-skills/anthropics/.source.json" >/dev/null

diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null
diff -qr "$SURFACE_BEFORE/codex" "$FIXTURE/home/.agents/skills" >/dev/null
cmp "$TMP_ROOT/manifest-before.json" "$FIXTURE/agent-tooling/skill-topology.json"
cmp "$TMP_ROOT/matrix-before.md" "$FIXTURE/agent-tooling/skills-matrix.md"
# selection-blind: pdf staged even though matrix/overrides exclude it
grep -F 'upstream fixture' "$FIXTURE/other-skills/anthropics/pdf/SKILL.md" >/dev/null
grep -F 'upstream fixture' "$FIXTURE/other-skills/anthropics/docx/SKILL.md" >/dev/null
# surfaces still hold pre-acquire content
grep -F 'preexisting surface' "$FIXTURE/home/.claude/skills/docx/SKILL.md" >/dev/null

# Idempotent second acquire
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/second.json"
jq -e '
  (.status == "clean" or .status == "reconciled") and
  (.errors | length) == 0 and
  (.changes | length) == 0
' "$FIXTURE/second.json" >/dev/null
diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null
diff -qr "$SURFACE_BEFORE/codex" "$FIXTURE/home/.agents/skills" >/dev/null

echo "update-skill-topology acquire tests passed"
