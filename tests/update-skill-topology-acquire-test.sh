#!/usr/bin/env bash
set -euo pipefail

# Acquire contract (ADR-0009): the network phase mirrors complete upstream
# inventories into tracked staging and touches nothing else — no surfaces, no
# matrix, no native plugins. --check is zero-write, including under HOME.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(command -v git)"
export REAL_GIT
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/acquire"
UPSTREAMS="$TMP_ROOT/upstreams"
BIN="$TMP_ROOT/bin"
export FAKE_UPSTREAM_ROOT="$UPSTREAMS"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/skills" \
  "$FIXTURE/other-skills/anthropics" "$FIXTURE/other-skills/matt" \
  "$FIXTURE/home/.agents/skills" "$FIXTURE/home/.claude/skills" \
  "$FIXTURE/runtime" "$UPSTREAMS" "$BIN"

cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$REPO_ROOT/agent-tooling/lib-staging.sh" \
  "$FIXTURE/agent-tooling/"
mkdir -p "$FIXTURE/agent-tooling/distribution-topology"
cp "$REPO_ROOT/agent-tooling/distribution-topology/lock.sh" \
  "$FIXTURE/agent-tooling/distribution-topology/"

seed_upstream() { # dir
  git -C "$1" init -q
  git -C "$1" config user.email tests@example.com
  git -C "$1" config user.name tests
  git -C "$1" add -A
  git -C "$1" commit -qm seed
}

# Flat source: skills/<name>/SKILL.md
FLAT="$UPSTREAMS/anthropics__skills"
mkdir -p "$FLAT/skills"
for skill in docx pdf pptx; do
  mkdir -p "$FLAT/skills/$skill"
  printf '%s\n' '---' "name: $skill" 'description: "upstream fixture"' '---' \
    > "$FLAT/skills/$skill/SKILL.md"
done
seed_upstream "$FLAT"

# Recursive source: nested SKILL.md paths under a subroot
NESTED="$UPSTREAMS/mattpocock__skills"
mkdir -p "$NESTED/skills/group/deep-skill" "$NESTED/skills/plain-skill"
printf '%s\n' '---' 'name: deep-skill' 'description: "nested fixture"' '---' \
  > "$NESTED/skills/group/deep-skill/SKILL.md"
printf '%s\n' '---' 'name: plain-skill' 'description: "nested fixture"' '---' \
  > "$NESTED/skills/plain-skill/SKILL.md"
seed_upstream "$NESTED"

# Fake git: rewrite GitHub URLs to local fixtures, keep everything else real.
cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
if [ "${1:-}" = -C ] && [ "${3:-}" = remote ] && [ "${4:-}" = get-url ]; then
  cat "$2/.fake-origin" 2>/dev/null || exit 1
  exit 0
fi
args=()
url=
for argument in "$@"; do
  case "$argument" in
    https://github.com/*)
      url="$argument"
      name="${argument#https://github.com/}"
      name="${name%.git}"
      args+=("$FAKE_UPSTREAM_ROOT/${name//\//__}")
      ;;
    *) args+=("$argument") ;;
  esac
done
"$REAL_GIT" "${args[@]}"
code=$?
if [ "$code" -eq 0 ] && [ -n "$url" ] && [ "${1:-}" = clone ]; then
  printf '%s\n' "$url" > "${@: -1}/.fake-origin"
fi
exit "$code"
BASH
chmod +x "$BIN/git"

cat > "$FIXTURE/agent-tooling/sources.json" <<'JSON'
{
  "version": 2,
  "sources": [
    {
      "id": "anthropic-skills",
      "classification": "source-only",
      "repo": "anthropics/skills",
      "subroot": "skills",
      "staging": "anthropics",
      "discovery": "flat"
    },
    {
      "id": "matt-skills",
      "classification": "npx-only",
      "repo": "mattpocock/skills",
      "subroot": "skills",
      "staging": "matt",
      "discovery": "recursive"
    },
    {
      "id": "waza",
      "classification": "dual-plugin",
      "repo": "tw93/Waza",
      "plugin": {
        "name": "waza",
        "marketplaces": { "claude": "waza", "codex": "waza" }
      }
    }
  ]
}
JSON

# Matrix that would select a subset — acquire must ignore it.
cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MD'
| Skill | Source | Type | Claude | Codex |
|---|---|---|---|---|
| `docx` | anthropics/skills | skill | Y | N |
| `pdf` | anthropics/skills | skill | N | N |
MD

# Pre-existing surface copies must stay byte-identical through acquire.
mkdir -p "$FIXTURE/home/.claude/skills/docx"
printf '%s\n' '---' 'name: docx' 'description: "preexisting surface"' '---' \
  > "$FIXTURE/home/.claude/skills/docx/SKILL.md"
printf '%s\n%s\n%s\n' "$FIXTURE/other-skills/anthropics/docx" skill-matrix deadbeef \
  > "$FIXTURE/home/.claude/skills/docx/.agent-scripts-copy"

# A tracked repo-owned skill of the same name keeps upstream mirror precedence.
mkdir -p "$FIXTURE/skills/plain-skill"
printf '%s\n' '---' 'name: plain-skill' 'description: "repo owned"' '---' \
  > "$FIXTURE/skills/plain-skill/SKILL.md"

# An orphan staged skill no longer upstream must be removed.
mkdir -p "$FIXTURE/other-skills/anthropics/ghost"
printf '%s\n' '---' 'name: ghost' 'description: "retired upstream"' '---' \
  > "$FIXTURE/other-skills/anthropics/ghost/SKILL.md"

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email tests@example.com
git -C "$FIXTURE" config user.name tests
git -C "$FIXTURE" add -A >/dev/null 2>&1
git -C "$FIXTURE" commit -qm fixture >/dev/null 2>&1

COMMAND="$FIXTURE/agent-tooling/update-skill-topology.sh"
SURFACE_BEFORE="$TMP_ROOT/surfaces-before"
mkdir -p "$SURFACE_BEFORE"
cp -R "$FIXTURE/home/.claude/skills" "$SURFACE_BEFORE/claude"
cp -R "$FIXTURE/home/.agents/skills" "$SURFACE_BEFORE/codex"
cp "$FIXTURE/agent-tooling/skills-matrix.md" "$TMP_ROOT/matrix-before.md"

run_acquire() {
  HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" "$COMMAND" "$@"
}

# --check: preview only, zero writes anywhere — including the HOME clone cache.
set +e
run_acquire --check --json > "$FIXTURE/check.json" 2> "$FIXTURE/check.err"
check_code=$?
set -e
test "$check_code" -eq 1
jq -e '.mode == "check" and .status == "drift" and (.errors | length) == 0' \
  "$FIXTURE/check.json" >/dev/null
jq -e 'any(.drift[]; .skill == "docx" and .action == "install")' "$FIXTURE/check.json" >/dev/null
jq -e 'any(.drift[]; .skill == "ghost" and .action == "remove")' "$FIXTURE/check.json" >/dev/null
[ ! -e "$FIXTURE/other-skills/anthropics/docx" ]
[ ! -e "$FIXTURE/home/.cache" ]
diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null
diff -qr "$SURFACE_BEFORE/codex" "$FIXTURE/home/.agents/skills" >/dev/null
cmp "$TMP_ROOT/matrix-before.md" "$FIXTURE/agent-tooling/skills-matrix.md"

# Reconcile: stages every upstream skill, removes orphans, records provenance.
run_acquire --json > "$FIXTURE/first.json"
jq -e '
  .mode == "reconcile" and .status == "reconciled" and (.errors | length) == 0 and
  any(.changes[]; .skill == "docx" and .action == "installed") and
  any(.changes[]; .skill == "pdf" and .action == "installed") and
  any(.changes[]; .skill == "pptx" and .action == "installed") and
  any(.changes[]; .skill == "deep-skill" and .action == "installed") and
  any(.changes[]; .skill == "ghost" and .action == "removed")
' "$FIXTURE/first.json" >/dev/null

for skill in docx pdf pptx; do
  test -f "$FIXTURE/other-skills/anthropics/$skill/SKILL.md"
done
# Recursive discovery reaches a nested skill and flattens it into staging.
test -f "$FIXTURE/other-skills/matt/deep-skill/SKILL.md"
# Upstream mirror precedence: a tracked repo-owned name is never staged.
[ ! -e "$FIXTURE/other-skills/matt/plain-skill" ]
# Orphan removed.
[ ! -e "$FIXTURE/other-skills/anthropics/ghost" ]
# Selection-blind: pdf staged even though the matrix excludes it.
grep -F 'upstream fixture' "$FIXTURE/other-skills/anthropics/pdf/SKILL.md" >/dev/null
# Markerless staging.
[ ! -e "$FIXTURE/other-skills/anthropics/docx/.agent-scripts-copy" ]
jq -e '.repo == "https://github.com/anthropics/skills.git" and (.commit | length) == 40' \
  "$FIXTURE/other-skills/anthropics/.source.json" >/dev/null

# Surfaces and matrix untouched by acquire.
diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null
diff -qr "$SURFACE_BEFORE/codex" "$FIXTURE/home/.agents/skills" >/dev/null
cmp "$TMP_ROOT/matrix-before.md" "$FIXTURE/agent-tooling/skills-matrix.md"
grep -F 'preexisting surface' "$FIXTURE/home/.claude/skills/docx/SKILL.md" >/dev/null
# Plugin-only sources are never staged.
[ ! -e "$FIXTURE/other-skills/waza" ]

# Idempotent second acquire.
run_acquire --json > "$FIXTURE/second.json"
jq -e '.status == "reconciled" and (.changes | length) == 0 and (.errors | length) == 0' \
  "$FIXTURE/second.json" >/dev/null
diff -qr "$SURFACE_BEFORE/claude" "$FIXTURE/home/.claude/skills" >/dev/null

# Upstream advancing restages just the changed skill.
printf '%s\n' '---' 'name: docx' 'description: "upstream moved"' '---' \
  > "$FLAT/skills/docx/SKILL.md"
git -C "$FLAT" commit -qam moved
run_acquire --json > "$FIXTURE/third.json"
jq -e 'any(.changes[]; .skill == "docx" and .action == "updated")' "$FIXTURE/third.json" >/dev/null
grep -F 'upstream moved' "$FIXTURE/other-skills/anthropics/docx/SKILL.md" >/dev/null

# An unexpected skills-lock entry is reported as a decision, never mutated.
mkdir -p "$FIXTURE/home/.agents"
cat > "$FIXTURE/home/.agents/.skill-lock.json" <<'JSON'
{"skills":{"stray":"someone/else","ask-matt":"mattpocock/skills"}}
JSON
cp "$FIXTURE/home/.agents/.skill-lock.json" "$TMP_ROOT/lock-before.json"
set +e
run_acquire --json > "$FIXTURE/lock.json"
lock_code=$?
set -e
test "$lock_code" -eq 3
jq -e '
  .status == "decision-required" and
  any(.decisions[]; .code == "unknown-npx-lock-source" and .skill == "stray") and
  any(.decisions[]; .code == "legacy-npx-lock-entry" and .skill == "ask-matt")
' "$FIXTURE/lock.json" >/dev/null
cmp "$TMP_ROOT/lock-before.json" "$FIXTURE/home/.agents/.skill-lock.json"

echo "update-skill-topology acquire tests passed"
