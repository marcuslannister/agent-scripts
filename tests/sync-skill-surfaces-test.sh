#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
export REAL_GIT
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/distribute"
BIN="$TMP_ROOT/bin"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/skills/repo-same" "$FIXTURE/other-skills/anthropics" \
  "$FIXTURE/home/.agents/skills" "$FIXTURE/home/.claude/skills" "$FIXTURE/home/.codex/skills/.system" \
  "$FIXTURE/runtime" "$BIN"

cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" \
  "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" \
  "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

# Network tools abort — offline contract must not touch them.
for tool in git curl ssh npm npx gh; do
  cat > "$BIN/$tool" <<'BASH'
#!/usr/bin/env bash
printf 'network tool blocked in distribute test: %s\n' "${0##*/}" >&2
exit 97
BASH
  chmod +x "$BIN/$tool"
done
# Real git only via REAL_GIT for fixture setup; runtime PATH uses blockers.
# Allow topology's internal `git ls-files` on the fixture repo through a narrow shim.
cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# Permit read-only fixture repo queries used by offline inventory filtering.
if [ "${1:-}" = -C ] && [ "${3:-}" = ls-files ]; then
  exec "$REAL_GIT" "$@"
fi
if [ "${1:-}" = ls-files ]; then
  exec "$REAL_GIT" "$@"
fi
printf 'network git blocked in distribute test: %s\n' "$*" >&2
exit 97
BASH
chmod +x "$BIN/git"

# Tracked staging only — no upstream clones.
for skill in docx pdf pptx foreign-same; do
  mkdir -p "$FIXTURE/other-skills/anthropics/$skill"
  printf '%s\n' '---' "name: $skill" 'description: "staged fixture"' '---' \
    > "$FIXTURE/other-skills/anthropics/$skill/SKILL.md"
done
printf '%s\n' '{"repo":"anthropics/skills","commit":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","syncedAt":"2026-07-25T00:00:00Z"}' \
  > "$FIXTURE/other-skills/anthropics/.source.json"

printf '%s\n' '---' 'name: repo-same' 'description: "repo fixture"' '---' \
  > "$FIXTURE/skills/repo-same/SKILL.md"

# Orphan managed surface copy owned by anthropic-skills.
mkdir -p "$FIXTURE/home/.agents/skills/old-orphan" "$FIXTURE/home/.claude/skills/old-orphan"
printf '%s\n' '---' 'name: old-orphan' 'description: "orphan"' '---' \
  > "$FIXTURE/home/.agents/skills/old-orphan/SKILL.md"
cp "$FIXTURE/home/.agents/skills/old-orphan/SKILL.md" \
  "$FIXTURE/home/.claude/skills/old-orphan/SKILL.md"
printf '%s\n%s\n%s\n' "$FIXTURE/other-skills/anthropics/old-orphan" anthropic-skills orphanhash \
  > "$FIXTURE/home/.agents/skills/old-orphan/.agent-scripts-copy"
cp "$FIXTURE/home/.agents/skills/old-orphan/.agent-scripts-copy" \
  "$FIXTURE/home/.claude/skills/old-orphan/.agent-scripts-copy"

# Legacy Claude root symlink — distribute must migrate.
rm -rf "$FIXTURE/home/.claude/skills"
ln -s "$FIXTURE/skills" "$FIXTURE/home/.claude/skills"

# Legacy Codex root noise — hygiene should migrate non-.system entries.
mkdir -p "$FIXTURE/home/.codex/skills/extra-noise"
printf 'noise\n' > "$FIXTURE/home/.codex/skills/extra-noise/file.txt"
printf 'system\n' > "$FIXTURE/home/.codex/skills/.system/keep.txt"

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
      "overrides": {}
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
  }
]
JSON

cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MD'
# Skills matrix

| Skill | Source | Type | Claude | Codex | Tokens |
| --- | --- | --- | --- | --- | --- |
| `repo-same` | steipete/agent-scripts | skill | Y | Y | ~1 |
| `docx` | anthropics/skills | skill | Y | Y | ~1 |
| `pdf` | anthropics/skills | skill | Y | N | ~1 |
| `pptx` | anthropics/skills | skill | N | Y | ~1 |
| `foreign-same` | anthropics/skills | skill | Y | Y | ~1 |
MD

"$REAL_GIT" -C "$FIXTURE" init -q
"$REAL_GIT" -C "$FIXTURE" add \
  skills/repo-same/SKILL.md \
  other-skills/anthropics \
  agent-tooling/skill-topology.json \
  agent-tooling/skills-matrix.md
# Keep distribution-topology etc untracked is fine; command runs from fixture copy.

COMMAND="$FIXTURE/agent-tooling/sync-skill-surfaces.sh"
export FAKE_HOME_PREFIX="$FIXTURE/home"

run_distribute() {
  HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
    "$COMMAND" "$@"
}

# --- --check previews drift offline without writes ---
cp -R "$FIXTURE/home" "$FIXTURE/home-before-check"
manifest_before="$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")"
matrix_before="$(shasum -a 256 "$FIXTURE/agent-tooling/skills-matrix.md")"
set +e
run_distribute --check --json > "$FIXTURE/check.json"
check_exit=$?
set -e
test "$check_exit" -eq 1
jq -e '.mode == "check" and (.status == "drift" or .status == "failed")' "$FIXTURE/check.json" >/dev/null
test "$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")" = "$manifest_before"
test "$(shasum -a 256 "$FIXTURE/agent-tooling/skills-matrix.md")" = "$matrix_before"
if ! diff -r "$FIXTURE/home-before-check" "$FIXTURE/home" >/dev/null; then
  echo "FAIL: distribute --check mutated HOME" >&2
  diff -r "$FIXTURE/home-before-check" "$FIXTURE/home" >&2 || true
  exit 1
fi

# --- fresh-machine distribute populates both surfaces offline ---
set +e
run_distribute --json > "$FIXTURE/first.json"
first_exit=$?
set -e
test "$first_exit" -eq 0
jq -e '.mode == "reconcile" and .status == "reconciled" and .errors == []' "$FIXTURE/first.json" >/dev/null

# Claude root migrated off symlink
test -d "$FIXTURE/home/.claude/skills"
test ! -L "$FIXTURE/home/.claude/skills"

# Surfaces populated from staging/repo only
for skill in docx foreign-same pdf repo-same; do
  test -f "$FIXTURE/home/.claude/skills/$skill/SKILL.md"
done
for skill in docx foreign-same pptx repo-same; do
  test -f "$FIXTURE/home/.agents/skills/$skill/SKILL.md"
done
test ! -e "$FIXTURE/home/.claude/skills/pptx"
test ! -e "$FIXTURE/home/.agents/skills/pdf"

# Markers point at tracked staging / repo sources
test "$(sed -n '1p' "$FIXTURE/home/.claude/skills/docx/.agent-scripts-copy")" = \
  "$FIXTURE/other-skills/anthropics/docx"
test "$(sed -n '2p' "$FIXTURE/home/.claude/skills/docx/.agent-scripts-copy")" = anthropic-skills
test "$(sed -n '2p' "$FIXTURE/home/.agents/skills/pptx/.agent-scripts-copy")" = anthropic-skills

# Orphans cleaned
test ! -e "$FIXTURE/home/.claude/skills/old-orphan"
test ! -e "$FIXTURE/home/.agents/skills/old-orphan"

# Codex root hygiene moved non-.system noise
test -d "$FIXTURE/home/.codex/skills/.system"
test ! -e "$FIXTURE/home/.codex/skills/extra-noise"
test -f "$FIXTURE/home/.codex/skills/.system/keep.txt"

# Matrix overrides persisted + report regenerated by distribute
jq -e '
  (.sources[] | select(.id == "anthropic-skills") |
    .matrixOverridesStart == "generated from agent-tooling/skills-matrix.md" and
    .overrides.docx == ["claude","codex"] and
    .overrides.pdf == ["claude"] and
    .overrides.pptx == ["codex"] and
    .overrides["foreign-same"] == ["claude","codex"]) and
  (.sources[] | select(.id == "repo-claude") |
    .overrides["repo-same"] == ["claude","codex"])
' "$FIXTURE/agent-tooling/skill-topology.json" >/dev/null
rg -q '\| `docx` \| anthropics/skills \| skill \| Y \| Y \|' "$FIXTURE/agent-tooling/skills-matrix.md"

# Staging provenance untouched by distribute
jq -e '.commit == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
  "$FIXTURE/other-skills/anthropics/.source.json" >/dev/null

# --- idempotent second run ---
run_distribute --json > "$FIXTURE/second.json"
jq -e '.status == "reconciled" and .changes == [] and .errors == []' "$FIXTURE/second.json" >/dev/null

# --- legacy Claude plain pointer file: preview, backup, migrate, repopulate ---
rm -rf "$FIXTURE/home/.claude/skills"
printf '../agent-scripts/skills' > "$FIXTURE/home/.claude/skills"
mkdir -p "$FIXTURE/home/.claude/skills-migrated-20260727-220000"
printf 'collision sentinel\n' > "$FIXTURE/home/.claude/skills-migrated-20260727-220000/keep"
set +e
AGENT_SCRIPTS_MIGRATION_TIMESTAMP=20260727-220000 \
  run_distribute --check --json > "$FIXTURE/pointer-check.json"
pointer_check_exit=$?
set -e
test "$pointer_check_exit" -eq 1
jq -e '.claudeRoot.state == "legacy-pointer" and .claudeRoot.action == "migrate" and
  any(.drift[]; .reason == "root-migration")' "$FIXTURE/pointer-check.json" >/dev/null
test "$(cat "$FIXTURE/home/.claude/skills")" = ../agent-scripts/skills
test ! -e "$FIXTURE/home/.claude/skills-migrated-20260727-220000-1"

AGENT_SCRIPTS_MIGRATION_TIMESTAMP=20260727-220000 \
  run_distribute --json > "$FIXTURE/pointer.json"
jq -e '.status == "reconciled" and .errors == []' "$FIXTURE/pointer.json" >/dev/null
test -d "$FIXTURE/home/.claude/skills"
test "$(sed -n '1p' "$FIXTURE/home/.claude/skills/.agent-scripts-root")" = claude-skills
test "$(cat "$FIXTURE/home/.claude/skills-migrated-20260727-220000-1/skills")" = ../agent-scripts/skills
test "$(cat "$FIXTURE/home/.claude/skills-migrated-20260727-220000/keep")" = 'collision sentinel'
for skill in docx foreign-same pdf repo-same; do
  test -f "$FIXTURE/home/.claude/skills/$skill/SKILL.md"
done

# --- missing staged skill selected by matrix: blocking error naming acquire ---
# Insert inside the live skill table (append after last skill row would miss if Counts follows).
awk '
  BEGIN { done = 0 }
  /^\| `foreign-same` \|/ && !done {
    print
    print "| `ghost-skill` | anthropics/skills | skill | Y | N | ~1 |"
    done = 1
    next
  }
  { print }
  END {
    if (!done) {
      print "| `ghost-skill` | anthropics/skills | skill | Y | N | ~1 |" > "/dev/stderr"
      exit 1
    }
  }
' "$FIXTURE/agent-tooling/skills-matrix.md" > "$FIXTURE/agent-tooling/skills-matrix.tmp"
mv "$FIXTURE/agent-tooling/skills-matrix.tmp" "$FIXTURE/agent-tooling/skills-matrix.md"
cp -R "$FIXTURE/home" "$FIXTURE/home-before-missing"
manifest_before_missing="$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")"
set +e
run_distribute --json > "$FIXTURE/missing.json" 2>"$FIXTURE/missing.err"
missing_exit=$?
set -e
if [ "$missing_exit" -ne 1 ]; then
  echo "expected missing-stage failure, got exit $missing_exit" >&2
  cat "$FIXTURE/missing.json" >&2 || true
  cat "$FIXTURE/missing.err" >&2 || true
  exit 1
fi
jq -e '
  .status == "failed" and
  any(.errors[]; test("ghost-skill") and test("acquire|git pull"))
' "$FIXTURE/missing.json" >/dev/null
# No surface mutation on hard fail
diff -r "$FIXTURE/home-before-missing" "$FIXTURE/home" >/dev/null
test "$(shasum -a 256 "$FIXTURE/agent-tooling/skill-topology.json")" = "$manifest_before_missing"
# restore matrix
cp "$FIXTURE/agent-tooling/skills-matrix.md" "$FIXTURE/skills-matrix.with-ghost.md"
# rewrite matrix without ghost
grep -v 'ghost-skill' "$FIXTURE/skills-matrix.with-ghost.md" > "$FIXTURE/agent-tooling/skills-matrix.md"

# --- acquire still green beside distribute ---
# Provide a fake upstream clone path so acquire can discover without real network:
# restore a git shim that serves local staged trees as "clone".
cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  mkdir -p "$(dirname "$destination")"
  mkdir -p "$destination/skills"
  # Clone body is whatever is currently staged under anthropics.
  cp -R "$FIXTURE_STAGING"/. "$destination/skills"/ 2>/dev/null || true
  # drop .source.json from skills root if copied
  rm -f "$destination/skills/.source.json"
  # fake git dir
  mkdir -p "$destination/.git"
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = pull ] && [ "${4:-}" = --ff-only ]; then
  printf 'Already up to date.\n'
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = rev-parse ] && [ "${4:-}" = HEAD ]; then
  printf 'cccccccccccccccccccccccccccccccccccccccc\n'
  exit 0
fi
if [ "${1:-}" = -C ] && [ "${3:-}" = ls-files ]; then
  exec "$REAL_GIT" "$@"
fi
if [ "${1:-}" = ls-files ]; then
  exec "$REAL_GIT" "$@"
fi
exec "$REAL_GIT" "$@"
BASH
chmod +x "$BIN/git"

ACQUIRE="$FIXTURE/agent-tooling/update-skill-topology.sh"
FIXTURE_STAGING="$FIXTURE/other-skills/anthropics"
export FIXTURE_STAGING
# Acquire needs Projects clone layout for anthropics skills suffix
mkdir -p "$FIXTURE/home/Projects"
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$ACQUIRE" --json > "$FIXTURE/acquire.json"
jq -e '.status == "reconciled" and .errors == []' "$FIXTURE/acquire.json" >/dev/null

echo "sync-skill-surfaces offline distribute tests passed"
