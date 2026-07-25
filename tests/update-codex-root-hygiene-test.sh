#!/usr/bin/env bash
set -euo pipefail

# Black-box Codex-root hygiene contract. The only public interface is the
# topology command; fixtures keep publication clean so hygiene is isolated.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_fixture() { # fixture_root
  local fixture_root="$1"
  mkdir -p \
    "$fixture_root/agent-tooling" \
    "$fixture_root/skills/fixture-skill" \
    "$fixture_root/home/.agents/skills" \
    "$fixture_root/home/.claude/skills" \
    "$fixture_root/runtime"
  cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$REPO_ROOT/agent-tooling/lib-copies.sh" "$fixture_root/agent-tooling/"
  cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$fixture_root/agent-tooling/"
  jq '[.[] | select(.sourceId == "repo-claude")]' \
    "$fixture_root/agent-tooling/distribution-topology/registry.json" > "$fixture_root/registry.tmp"
  mv "$fixture_root/registry.tmp" "$fixture_root/agent-tooling/distribution-topology/registry.json"
  printf '%s\n' '---' 'name: fixture-skill' 'description: "fixture"' '---' > "$fixture_root/skills/fixture-skill/SKILL.md"
  printf 'claude-skills\n' > "$fixture_root/home/.claude/skills/.agent-scripts-root"
  cat > "$fixture_root/agent-tooling/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {"fixture-skill": []}
    }
  ]
}
JSON
  git -C "$fixture_root" init -q
  git -C "$fixture_root" add skills
}

run_topology() { # fixture_root mode output
  local fixture_root="$1"
  local mode="$2"
  local output="$3"
  set +e
  HOME="$fixture_root/home" \
  TMPDIR="$fixture_root/runtime" \
  AGENT_SCRIPTS_MIGRATION_TIMESTAMP=20260714-120000 \
    "$fixture_root/agent-tooling/update-skill-topology.sh" $mode --json > "$output"
  RUN_EXIT=$?
  set -e
}

# Root symlink: check reports drift without writes; reconcile backs up the
# link itself, recreates a real legacy root, and leaves instruction files alone.
ROOT_LINK="$TMP_ROOT/root-link"
make_fixture "$ROOT_LINK"
mkdir -p "$ROOT_LINK/home/.codex"
ln -s "$ROOT_LINK/skills" "$ROOT_LINK/home/.codex/skills"
run_topology "$ROOT_LINK" --check "$ROOT_LINK/check.json"
test "$RUN_EXIT" -eq 1
test -L "$ROOT_LINK/home/.codex/skills"
test ! -e "$ROOT_LINK/home/.codex/skills-migrated-20260714-120000"
jq -e '
  .status == "drift" and .hygiene.status == "drift" and
  .hygiene.entries == [{"name":"skills","kind":"root-symlink"}] and
  .hygiene.changes == []
' "$ROOT_LINK/check.json" >/dev/null

run_topology "$ROOT_LINK" '' "$ROOT_LINK/reconcile.json"
test "$RUN_EXIT" -eq 0
test -d "$ROOT_LINK/home/.codex/skills"
test ! -L "$ROOT_LINK/home/.codex/skills"
test -L "$ROOT_LINK/home/.codex/skills-migrated-20260714-120000/skills"
test ! -e "$ROOT_LINK/home/.codex/AGENTS.md"
jq -e '
  .status == "reconciled" and .hygiene.status == "clean" and
  .hygiene.entries == [] and
  (.hygiene.changes[] | .name == "skills" and .kind == "root-symlink" and
    (.backupPath | endswith("skills-migrated-20260714-120000/skills")))
' "$ROOT_LINK/reconcile.json" >/dev/null

run_topology "$ROOT_LINK" '' "$ROOT_LINK/rerun.json"
test "$RUN_EXIT" -eq 0
jq -e '.status == "reconciled" and .hygiene.status == "clean" and .hygiene.changes == []' "$ROOT_LINK/rerun.json" >/dev/null
test ! -e "$ROOT_LINK/home/.codex/skills-migrated-20260714-120000-1"

# Real root: preserve .system; migrate directories, nested contents, symlinks,
# and pointer files. Existing active Codex-surface content is never overwritten.
ENTRIES="$TMP_ROOT/entries"
make_fixture "$ENTRIES"
mkdir -p \
  "$ENTRIES/home/.codex/skills/.system/bundled" \
  "$ENTRIES/home/.codex/skills/legacy-dir/nested" \
  "$ENTRIES/home/.agents/skills/legacy-dir" \
  "$ENTRIES/home/.codex/skills-migrated-20260714-120000"
printf 'legacy\n' > "$ENTRIES/home/.codex/skills/legacy-dir/nested/SKILL.md"
printf 'active\n' > "$ENTRIES/home/.agents/skills/legacy-dir/SKILL.md"
ln -s "$ENTRIES/skills/fixture-skill" "$ENTRIES/home/.codex/skills/legacy-link"
printf '%s\n' "$ENTRIES/skills/fixture-skill" > "$ENTRIES/home/.codex/skills/pointer-file"
printf 'collision sentinel\n' > "$ENTRIES/home/.codex/skills-migrated-20260714-120000/keep"

run_topology "$ENTRIES" --check "$ENTRIES/check.json"
test "$RUN_EXIT" -eq 1
jq -e '
  .hygiene.status == "drift" and
  ([.hygiene.entries[] | {name,kind}] == [
    {"name":"legacy-dir","kind":"directory"},
    {"name":"legacy-link","kind":"symlink"},
    {"name":"pointer-file","kind":"file"}
  ])
' "$ENTRIES/check.json" >/dev/null

run_topology "$ENTRIES" '' "$ENTRIES/reconcile.json"
test "$RUN_EXIT" -eq 0
BACKUP="$ENTRIES/home/.codex/skills-migrated-20260714-120000-1"
test -d "$ENTRIES/home/.codex/skills/.system"
test -f "$BACKUP/legacy-dir/nested/SKILL.md"
test -L "$BACKUP/legacy-link"
test -f "$BACKUP/pointer-file"
test "$(cat "$ENTRIES/home/.agents/skills/legacy-dir/SKILL.md")" = active
test "$(cat "$ENTRIES/home/.codex/skills-migrated-20260714-120000/keep")" = "collision sentinel"
test -z "$(find "$ENTRIES/home/.codex/skills" -mindepth 1 -maxdepth 1 ! -name .system -print -quit)"
jq -e --arg backup "$BACKUP" '
  .hygiene.status == "clean" and .hygiene.entries == [] and
  ([.hygiene.changes[].backupPath] | unique) == [$backup + "/legacy-dir", $backup + "/legacy-link", $backup + "/pointer-file"]
' "$ENTRIES/reconcile.json" >/dev/null

# Partial failure: successful moves stay backed up, blocked entry stays active,
# the run fails observably, and a rerun completes into a collision-safe backup.
BLOCKED="$TMP_ROOT/blocked"
make_fixture "$BLOCKED"
mkdir -p "$BLOCKED/home/.codex/skills/.system" "$BLOCKED/home/.codex/skills/moved-dir"
printf 'stuck\n' > "$BLOCKED/home/.codex/skills/blocked-file"
mkdir -p "$BLOCKED/failbin"
REAL_MV="$(command -v mv)"
cat > "$BLOCKED/failbin/mv" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in */blocked-file) exit 1 ;; esac
done
exec "$REAL_MV" "\$@"
EOF
chmod +x "$BLOCKED/failbin/mv"

set +e
HOME="$BLOCKED/home" \
TMPDIR="$BLOCKED/runtime" \
PATH="$BLOCKED/failbin:$PATH" \
AGENT_SCRIPTS_MIGRATION_TIMESTAMP=20260714-120000 \
  "$BLOCKED/agent-tooling/update-skill-topology.sh" --json > "$BLOCKED/failed.json"
blocked_exit=$?
set -e
test "$blocked_exit" -eq 1
test -d "$BLOCKED/home/.codex/skills-migrated-20260714-120000/moved-dir"
test "$(cat "$BLOCKED/home/.codex/skills/blocked-file")" = stuck
jq -e '
  .status == "failed" and .hygiene.status == "failed" and
  .hygiene.entries == [{"name":"blocked-file","kind":"file"}] and
  any(.errors[]; contains("could not migrate legacy Codex-root entry") and contains("blocked-file"))
' "$BLOCKED/failed.json" >/dev/null

run_topology "$BLOCKED" '' "$BLOCKED/recovered.json"
test "$RUN_EXIT" -eq 0
test -f "$BLOCKED/home/.codex/skills-migrated-20260714-120000-1/blocked-file"
jq -e '.status == "reconciled" and .hygiene.status == "clean" and .hygiene.entries == []' "$BLOCKED/recovered.json" >/dev/null

echo "Codex-root hygiene tests passed"
