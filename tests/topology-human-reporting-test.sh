#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
HOME_ROOT="$TMP_ROOT/home"
mkdir -p \
  "$FIXTURE/agent-tooling/distribution-topology" \
  "$FIXTURE/skills/alpha" \
  "$HOME_ROOT/.claude/skills" \
  "$HOME_ROOT/.agents/skills" \
  "$TMP_ROOT/runtime"
cp "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/distribution-topology/distribute.sh" \
  "$REPO_ROOT/agent-tooling/distribution-topology/lock.sh" \
  "$FIXTURE/agent-tooling/distribution-topology/"
printf '%s\n' fixture > "$FIXTURE/skills/alpha/SKILL.md"
cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `alpha` | ignored | skill | Y | N | ~1 |
MARKDOWN

COMMAND="$FIXTURE/agent-tooling/sync-skill-surfaces.sh"
run_distribute() {
  HOME="$HOME_ROOT" TMPDIR="$TMP_ROOT/runtime" "$COMMAND" "$@"
}

set +e
run_distribute --check > "$FIXTURE/check.out" 2> "$FIXTURE/check.err"
check_exit=$?
set -e
test "$check_exit" -eq 1
test ! -s "$FIXTURE/check.err"
rg -F 'Skill surface check: drift' "$FIXTURE/check.out" >/dev/null
rg -F -- '- install alpha on claude (missing)' "$FIXTURE/check.out" >/dev/null

run_distribute > "$FIXTURE/reconcile.out" 2> "$FIXTURE/reconcile.err"
test ! -s "$FIXTURE/reconcile.err"
rg -F 'Skill surface reconcile: reconciled' "$FIXTURE/reconcile.out" >/dev/null
rg -F -- '- installed alpha on claude' "$FIXTURE/reconcile.out" >/dev/null

run_distribute --check --json > "$FIXTURE/result.json" 2> "$FIXTURE/result.err"
test ! -s "$FIXTURE/result.err"
jq -e '.schemaVersion == 1 and .status == "clean"' "$FIXTURE/result.json" >/dev/null
! rg -q 'Skill surface|\x1b\[' "$FIXTURE/result.json"

rm -rf "$HOME_ROOT/.claude/skills/alpha"
mkdir -p "$HOME_ROOT/.claude/skills/alpha"
printf '%s\n' local > "$HOME_ROOT/.claude/skills/alpha/local.txt"
set +e
run_distribute --check > "$FIXTURE/collision.out" 2> "$FIXTURE/collision.err"
collision_exit=$?
set -e
test "$collision_exit" -eq 1
rg -F 'Skill surface check: failed' "$FIXTURE/collision.out" >/dev/null
rg -F 'unmarked directory blocks selected skill alpha' "$FIXTURE/collision.err" >/dev/null

echo "topology human reporting tests passed"
