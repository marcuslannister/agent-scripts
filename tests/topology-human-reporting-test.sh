#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/fixture"
mkdir -p \
  "$FIXTURE/scripts" \
  "$FIXTURE/skills/alpha" \
  "$FIXTURE/home/.agents/skills" \
  "$FIXTURE/runtime"
cp "$REPO_ROOT/scripts/update-skill-topology.sh" "$REPO_ROOT/scripts/lib-copies.sh" "$FIXTURE/scripts/"
cp -R "$REPO_ROOT/scripts/distribution-topology" "$FIXTURE/scripts/"
jq '[.[] | select(.sourceId == "repo-claude")]' \
  "$FIXTURE/scripts/distribution-topology/registry.json" > "$FIXTURE/registry.tmp"
mv "$FIXTURE/registry.tmp" "$FIXTURE/scripts/distribution-topology/registry.json"
printf '%s\n' '---' 'name: alpha' 'description: "fixture"' '---' > "$FIXTURE/skills/alpha/SKILL.md"
cat > "$FIXTURE/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {"alpha": ["claude", "codex"]}
    }
  ]
}
JSON
git -C "$FIXTURE" init -q
git -C "$FIXTURE" add skills
source "$FIXTURE/scripts/lib-copies.sh"
install_skill_copy "$FIXTURE/skills/alpha" "$FIXTURE/home/.agents/skills/alpha" repo-skills

mv "$FIXTURE/scripts/distribution-topology/adapters/repo-owned.sh" \
  "$FIXTURE/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$FIXTURE/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${4:-}" = discover ] && [ -n "${TOPOLOGY_BLOCK_STARTED:-}" ]; then
  : > "$TOPOLOGY_BLOCK_STARTED"
  while [ ! -e "$TOPOLOGY_BLOCK_RELEASE" ]; do sleep 0.05; done
fi
if [ "${4:-}" = discover ] && [ "${TOPOLOGY_FAIL_DISCOVER:-0}" = 1 ]; then
  printf 'fixture discovery failure\n' >&2
  exit 1
fi
if [ "${4:-}" = verify ] && [ "${TOPOLOGY_FAIL_VERIFY:-0}" = 1 ]; then
  printf 'fixture verification failure\n' >&2
  exit 1
fi
exec "${BASH_SOURCE[0]%/*}/repo-owned-real.sh" "$@"
BASH
chmod +x "$FIXTURE/scripts/distribution-topology/adapters/repo-owned.sh"
COMMAND="$FIXTURE/scripts/update-skill-topology.sh"

assert_row() {
  local output="$1" source="$2" destination="$3" change="$4" result="$5"
  awk -v source="$source" -v destination="$destination" -v change="$change" -v result="$result" '
    $1 == source && $2 == destination && $3 == change && $4 == result { found=1 }
    END { exit !found }
  ' "$output"
}

# Progress reaches stdout before a blocked discovery adapter finishes.
TOPOLOGY_BLOCK_STARTED="$FIXTURE/progress.started" \
TOPOLOGY_BLOCK_RELEASE="$FIXTURE/progress.release" \
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" \
  > "$FIXTURE/progress.out" 2> "$FIXTURE/progress.err" &
progress_pid=$!
for _ in {1..100}; do
  [ -e "$FIXTURE/progress.started" ] && break
  sleep 0.05
done
test -e "$FIXTURE/progress.started"
kill -0 "$progress_pid"
grep -F '[1/4] Discovering sources' "$FIXTURE/progress.out" >/dev/null
! grep -F 'SOURCE' "$FIXTURE/progress.out" >/dev/null
: > "$FIXTURE/progress.release"
wait "$progress_pid"
test ! -s "$FIXTURE/progress.err"

for stage in \
  '[1/4] Discovering sources' \
  '[2/4] Planning topology' \
  '[3/4] Executing adapters' \
  '[4/4] Verifying final topology'; do
  grep -F "$stage" "$FIXTURE/progress.out" >/dev/null
done
grep -Eq '^SOURCE +DESTINATION +CHANGE +RESULT$' "$FIXTURE/progress.out"
assert_row "$FIXTURE/progress.out" repo-claude claude,codex none clean
awk '
  /\[1\/4\] Discovering sources/ { discover=NR }
  /\[2\/4\] Planning topology/ { plan=NR }
  /\[3\/4\] Executing adapters/ { execute=NR }
  /\[4\/4\] Verifying final topology/ { verify=NR }
  /^SOURCE +DESTINATION +CHANGE +RESULT$/ { table=NR }
  END { exit !(discover < plan && plan < execute && execute < verify && verify < table) }
' "$FIXTURE/progress.out"

# JSON stays one undecorated document.
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check --json \
  > "$FIXTURE/result.json" 2> "$FIXTURE/result-json.err"
test ! -s "$FIXTURE/result-json.err"
jq -e '.schemaVersion == 1 and .status == "clean"' "$FIXTURE/result.json" >/dev/null
! rg -q '\[[1-4]/4\]|SOURCE|\x1b\[' "$FIXTURE/result.json"

# Check drift and reconcile changes both use the final result table.
rm -rf "$FIXTURE/home/.agents/skills/alpha"
set +e
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/drift.out" 2> "$FIXTURE/drift.err"
drift_exit=$?
set -e
test "$drift_exit" -eq 1
test ! -s "$FIXTURE/drift.err"
grep -F '[3/4] Inspecting adapters' "$FIXTURE/drift.out" >/dev/null
grep -F '[4/4] Final verification' "$FIXTURE/drift.out" >/dev/null
assert_row "$FIXTURE/drift.out" repo-claude/alpha codex missing drift

HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" \
  > "$FIXTURE/changed.out" 2> "$FIXTURE/changed.err"
test ! -s "$FIXTURE/changed.err"
assert_row "$FIXTURE/changed.out" repo-claude/alpha codex installed changed

# Decision-required and failed outcomes retain rows; diagnostics stay stderr.
marker="$FIXTURE/home/.agents/skills/alpha/.agent-scripts-copy"
printf '%s\n%s\n%s\n' "$(sed -n '1p' "$marker")" other-owner "$(sed -n '3p' "$marker")" > "$marker"
set +e
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/decision.out" 2> "$FIXTURE/decision.err"
decision_exit=$?
set -e
test "$decision_exit" -eq 3
assert_row "$FIXTURE/decision.out" repo-claude/alpha codex surface-ownership-collision decision-required
grep -F 'Decision required:' "$FIXTURE/decision.err" >/dev/null

printf '%s\n%s\n%s\n' "$(sed -n '1p' "$marker")" repo-skills "$(sed -n '3p' "$marker")" > "$marker"
set +e
TOPOLOGY_FAIL_VERIFY=1 HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" \
  > "$FIXTURE/failed.out" 2> "$FIXTURE/failed.err"
failed_exit=$?
set -e
test "$failed_exit" -eq 1
assert_row "$FIXTURE/failed.out" repo-claude claude,codex none failed
grep -F 'error: source repo-claude verification failed: fixture verification failure' "$FIXTURE/failed.err" >/dev/null

set +e
TOPOLOGY_FAIL_DISCOVER=1 HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/check-failed.out" 2> "$FIXTURE/check-failed.err"
check_failed_exit=$?
set -e
test "$check_failed_exit" -eq 1
grep -Eq '^SOURCE +DESTINATION +CHANGE +RESULT$' "$FIXTURE/check-failed.out"
assert_row "$FIXTURE/check-failed.out" topology - failed failed
grep -F 'Result: failed' "$FIXTURE/check-failed.out" >/dev/null
grep -F 'error: source repo-claude discovery failed: fixture discovery failure' "$FIXTURE/check-failed.err" >/dev/null

# Removals remain explicit.
jq '.sources[0].overrides.alpha = ["claude"]' "$FIXTURE/skill-topology.json" > "$FIXTURE/manifest.tmp"
mv "$FIXTURE/manifest.tmp" "$FIXTURE/skill-topology.json"
set +e
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/remove-check.out" 2> "$FIXTURE/remove-check.err"
remove_check_exit=$?
set -e
test "$remove_check_exit" -eq 1
test ! -s "$FIXTURE/remove-check.err"
assert_row "$FIXTURE/remove-check.out" repo-claude/alpha codex planned-removal drift

HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" \
  > "$FIXTURE/removed.out" 2> "$FIXTURE/removed.err"
test ! -s "$FIXTURE/removed.err"
assert_row "$FIXTURE/removed.out" repo-claude/alpha codex removed changed

# ANSI color: TTY only; NO_COLOR always wins.
script -q /dev/null env -u NO_COLOR HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/tty.out" 2> "$FIXTURE/tty.err"
rg -q $'\033\[' "$FIXTURE/tty.out"
script -q /dev/null env NO_COLOR=1 HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" "$COMMAND" --check \
  > "$FIXTURE/no-color.out" 2> "$FIXTURE/no-color.err"
! rg -q $'\033\[' "$FIXTURE/no-color.out"
! rg -q $'\033\[' "$FIXTURE/progress.out"

printf 'topology human reporting tests passed\n'
