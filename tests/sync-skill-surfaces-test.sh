#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
HOME_ROOT="$TMP_ROOT/home"
RUNTIME="$TMP_ROOT/runtime"
BIN="$TMP_ROOT/bin"
mkdir -p \
  "$FIXTURE/agent-tooling/distribution-topology" \
  "$FIXTURE/skills/repo-both" \
  "$FIXTURE/other-skills/alpha/claude-only" \
  "$FIXTURE/other-skills/beta/codex-only" \
  "$HOME_ROOT/.claude/skills" \
  "$HOME_ROOT/.agents/skills" \
  "$RUNTIME" \
  "$BIN"

for tool in git curl ssh npm npx gh; do
  printf '%s\n' '#!/usr/bin/env bash' 'echo "network tool called: ${0##*/}" >&2' 'exit 97' \
    > "$BIN/$tool"
  chmod +x "$BIN/$tool"
done

cp "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" \
  "$REPO_ROOT/agent-tooling/lib-copies.sh" \
  "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/distribution-topology/lock.sh" \
  "$FIXTURE/agent-tooling/distribution-topology/"
if [ -f "$REPO_ROOT/agent-tooling/distribution-topology/distribute.sh" ]; then
  cp "$REPO_ROOT/agent-tooling/distribution-topology/distribute.sh" \
    "$FIXTURE/agent-tooling/distribution-topology/"
fi

for path in \
  skills/repo-both \
  other-skills/alpha/claude-only \
  other-skills/beta/codex-only; do
  skill="${path##*/}"
  printf '%s\n' '---' "name: $skill" 'description: fixture' '---' \
    > "$FIXTURE/$path/SKILL.md"
done

cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
# Skills matrix

| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `claude-only` | ignored/source | skill | Y | N | ~1 |
| `codex-only` | ignored/source | skill | N | Y | ~1 |
| `repo-both` | ignored/source | skill | Y | Y | ~1 |
MARKDOWN

COMMAND="$FIXTURE/agent-tooling/sync-skill-surfaces.sh"
run_distribute() {
  HOME="$HOME_ROOT" TMPDIR="$RUNTIME" PATH="$BIN:$PATH" "$COMMAND" "$@"
}

mtime() {
  if stat -c %Y "$1" >/dev/null 2>&1; then
    stat -c %Y "$1"
  else
    stat -f %m "$1"
  fi
}

# Structurally invalid matrices fail before touching either surface.
cp "$FIXTURE/agent-tooling/skills-matrix.md" "$FIXTURE/agent-tooling/skills-matrix.valid"
printf '%s\n' '| `repo-both` | duplicate/source | skill | Y | Y | ~1 |' \
  >> "$FIXTURE/agent-tooling/skills-matrix.md"
set +e
run_distribute --json > "$FIXTURE/invalid.json"
invalid_exit=$?
set -e
test "$invalid_exit" -eq 2
jq -e '.status == "invalid" and any(.errors[]; contains("duplicate skill row"))' \
  "$FIXTURE/invalid.json" >/dev/null
test ! -e "$HOME_ROOT/.claude/skills/repo-both"
test ! -e "$HOME_ROOT/.agents/skills/repo-both"
mv "$FIXTURE/agent-tooling/skills-matrix.valid" "$FIXTURE/agent-tooling/skills-matrix.md"

set +e
run_distribute --check --json > "$FIXTURE/check.json"
check_exit=$?
set -e
test "$check_exit" -eq 1
jq -e '
  .mode == "check" and .status == "drift" and .errors == [] and
  any(.plan[]; .skill == "claude-only" and .destinations == ["claude"]) and
  any(.plan[]; .skill == "codex-only" and .destinations == ["codex"]) and
  any(.plan[]; .skill == "repo-both" and .destinations == ["claude", "codex"])
' "$FIXTURE/check.json" >/dev/null
test ! -e "$HOME_ROOT/.claude/skills/claude-only"
test ! -e "$HOME_ROOT/.agents/skills/codex-only"

run_distribute --json > "$FIXTURE/result.json"
jq -e '.mode == "reconcile" and .status == "reconciled" and .errors == []' \
  "$FIXTURE/result.json" >/dev/null

test -f "$HOME_ROOT/.claude/skills/claude-only/SKILL.md"
test ! -e "$HOME_ROOT/.agents/skills/claude-only"
test -f "$HOME_ROOT/.agents/skills/codex-only/SKILL.md"
test ! -e "$HOME_ROOT/.claude/skills/codex-only"
test -f "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"
test -f "$HOME_ROOT/.agents/skills/repo-both/SKILL.md"

test "$(sed -n '2p' "$HOME_ROOT/.claude/skills/claude-only/.agent-scripts-copy")" = skill-matrix
test "$(sed -n '2p' "$HOME_ROOT/.agents/skills/codex-only/.agent-scripts-copy")" = skill-matrix

# Repo-owned skills take precedence over same-named foreign staging.
mkdir -p "$FIXTURE/other-skills/alpha/repo-both"
printf '%s\n' foreign-copy > "$FIXTURE/other-skills/alpha/repo-both/SKILL.md"
test "$(sed -n '1p' "$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy")" = \
  "$FIXTURE/skills/repo-both"

# An unchanged second run performs no writes.
marker_mtime="$(mtime "$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy")"
test -f "$HOME_ROOT/.claude/skills/claude-only/.agent-scripts-copy"
test -f "$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy"
set +e
run_distribute --json > "$FIXTURE/unchanged.json"
unchanged_exit=$?
set -e
if [ "$unchanged_exit" -ne 0 ]; then
  eza -la "$HOME_ROOT/.claude/skills/claude-only" >&2
  eza -la "$HOME_ROOT/.claude/skills/repo-both" >&2
  cat "$FIXTURE/unchanged.json" >&2
  exit "$unchanged_exit"
fi
jq -e '.status == "reconciled" and .changes == [] and .drift == []' \
  "$FIXTURE/unchanged.json" >/dev/null
test "$(mtime "$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy")" = "$marker_mtime"

# Changed tracked content is previewed without writes, then refreshed.
printf '%s\n' changed >> "$FIXTURE/skills/repo-both/SKILL.md"
set +e
run_distribute --check --json > "$FIXTURE/changed-check.json"
changed_check_exit=$?
set -e
test "$changed_check_exit" -eq 1
jq -e 'any(.drift[]; .skill == "repo-both" and .reason == "changed")' \
  "$FIXTURE/changed-check.json" >/dev/null
if rg -q changed "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"; then
  echo 'check mode rewrote a changed copy' >&2
  exit 1
fi
run_distribute --json > "$FIXTURE/changed.json"
rg -q changed "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"
rg -q changed "$HOME_ROOT/.agents/skills/repo-both/SKILL.md"

# Unmarked directories survive and are reported.
mkdir -p "$HOME_ROOT/.claude/skills/local-only"
printf '%s\n' keep > "$HOME_ROOT/.claude/skills/local-only/keep.txt"
run_distribute --json > "$FIXTURE/unmarked.json"
test -f "$HOME_ROOT/.claude/skills/local-only/keep.txt"
jq -e 'any(.skipped[]; .skill == "local-only" and .reason == "unmarked-directory")' \
  "$FIXTURE/unmarked.json" >/dev/null

# A pre-marker copy of a selected skill is adopted rather than blocking it.
adopt_marker="$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy"
rm -f "$adopt_marker"
run_distribute --json > "$FIXTURE/adoptable.json"
jq -e '
  .status == "reconciled" and .errors == [] and
  (any(.skipped[]; .skill == "repo-both") | not) and
  (any(.warnings[]; .message | contains("repo-both")) | not) and
  any(.changes[]; .skill == "repo-both" and .destination == "claude")
' "$FIXTURE/adoptable.json" >/dev/null
test "$(sed -n '2p' "$adopt_marker")" = skill-matrix

# An unmarked directory holding the user's own content still blocks its skill.
rm -f "$HOME_ROOT/.claude/skills/claude-only/.agent-scripts-copy"
printf '%s\n' user-authored > "$HOME_ROOT/.claude/skills/claude-only/SKILL.md"
set +e
run_distribute --json > "$FIXTURE/unadoptable.json"
unadoptable_exit=$?
set -e
test "$unadoptable_exit" -eq 1
jq -e '
  any(.errors[]; contains("unmarked directory blocks selected skill claude-only")) and
  any(.skipped[]; .skill == "claude-only" and .reason == "unmarked-directory")
' "$FIXTURE/unadoptable.json" >/dev/null
rg -q user-authored "$HOME_ROOT/.claude/skills/claude-only/SKILL.md"
rm -rf "$HOME_ROOT/.claude/skills/claude-only"
run_distribute --json > "$FIXTURE/unadoptable-restored.json"
test "$(sed -n '2p' "$HOME_ROOT/.claude/skills/claude-only/.agent-scripts-copy")" = skill-matrix

# Pre-cutover agent-scripts owners are adopted or cleaned during the first sync.
repo_marker="$HOME_ROOT/.claude/skills/repo-both/.agent-scripts-copy"
repo_source="$(sed -n '1p' "$repo_marker")"
repo_hash="$(sed -n '3p' "$repo_marker")"
printf '%s\n%s\n%s\n' "$repo_source" repo-skills "$repo_hash" > "$repo_marker"
run_distribute --json > "$FIXTURE/legacy-selected.json"
test "$(sed -n '2p' "$repo_marker")" = skill-matrix
jq -e 'any(.changes[]; .skill == "repo-both" and .destination == "claude")' \
  "$FIXTURE/legacy-selected.json" >/dev/null

mkdir -p "$HOME_ROOT/.claude/skills/legacy-unselected"
printf '%s\n' remove > "$HOME_ROOT/.claude/skills/legacy-unselected/SKILL.md"
printf '%s\n%s\n%s\n' /legacy/source matt-skills legacy-hash \
  > "$HOME_ROOT/.claude/skills/legacy-unselected/.agent-scripts-copy"
run_distribute --json > "$FIXTURE/legacy-unselected.json"
test ! -e "$HOME_ROOT/.claude/skills/legacy-unselected"
jq -e 'any(.changes[]; .skill == "legacy-unselected" and .action == "removed")' \
  "$FIXTURE/legacy-unselected.json" >/dev/null

# Foreign-owned marked directories are preserved, whether selected or not.
mkdir -p "$HOME_ROOT/.claude/skills/foreign-owned"
printf '%s\n' keep > "$HOME_ROOT/.claude/skills/foreign-owned/keep.txt"
printf '%s\n%s\n%s\n' /foreign/source another-tool foreign-hash \
  > "$HOME_ROOT/.claude/skills/foreign-owned/.agent-scripts-copy"
run_distribute --json > "$FIXTURE/foreign-unselected.json"
test -f "$HOME_ROOT/.claude/skills/foreign-owned/keep.txt"
jq -e 'any(.skipped[]; .skill == "foreign-owned" and .reason == "other-owner")' \
  "$FIXTURE/foreign-unselected.json" >/dev/null

repo_hash="$(sed -n '3p' "$repo_marker")"
printf '%s\n%s\n%s\n' "$repo_source" another-tool "$repo_hash" > "$repo_marker"
printf '%s\n' foreign-edit >> "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"
set +e
run_distribute --json > "$FIXTURE/foreign-selected.json"
foreign_selected_exit=$?
set -e
test "$foreign_selected_exit" -eq 1
jq -e '
  any(.errors[]; contains("foreign-owned directory blocks selected skill repo-both")) and
  any(.skipped[]; .skill == "repo-both" and .reason == "other-owner")
' "$FIXTURE/foreign-selected.json" >/dev/null
rg -q foreign-edit "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"
printf '%s\n%s\n%s\n' "$repo_source" skill-matrix "$repo_hash" > "$repo_marker"
run_distribute --json > "$FIXTURE/foreign-restored.json"
! rg -q foreign-edit "$HOME_ROOT/.claude/skills/repo-both/SKILL.md"

# Ambiguous and unresolved selections are collected while resolvable work applies.
mkdir -p \
  "$FIXTURE/other-skills/alpha/ambiguous" \
  "$FIXTURE/other-skills/beta/ambiguous" \
  "$FIXTURE/other-skills/alpha/still-applies"
printf '%s\n' alpha > "$FIXTURE/other-skills/alpha/ambiguous/SKILL.md"
printf '%s\n' beta > "$FIXTURE/other-skills/beta/ambiguous/SKILL.md"
printf '%s\n' valid > "$FIXTURE/other-skills/alpha/still-applies/SKILL.md"
mkdir -p "$HOME_ROOT/.agents/skills/ghost"
printf '%s\n' preserve-unresolved > "$HOME_ROOT/.agents/skills/ghost/SKILL.md"
printf '%s\n%s\n%s\n' /retired/ghost skill-matrix retired-hash \
  > "$HOME_ROOT/.agents/skills/ghost/.agent-scripts-copy"
perl -0pi -e 's/\| `codex-only` \| ignored\/source \| skill \| N \| Y \| ~1 \|/| `codex-only` | ignored\/source | skill | N | N | ~1 |/' \
  "$FIXTURE/agent-tooling/skills-matrix.md"
cat >> "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
| `ambiguous` | ignored/source | skill | Y | N | ~1 |
| `ghost` | ignored/source | skill | N | Y | ~1 |
| `still-applies` | ignored/source | skill | Y | Y | ~1 |
MARKDOWN
set +e
run_distribute --json > "$FIXTURE/partial-failure.json"
partial_exit=$?
set -e
test "$partial_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("ambiguous") and contains("alpha") and contains("beta")) and
  any(.errors[]; contains("ghost"))
' "$FIXTURE/partial-failure.json" >/dev/null
test -f "$HOME_ROOT/.claude/skills/still-applies/SKILL.md"
test -f "$HOME_ROOT/.agents/skills/still-applies/SKILL.md"
test ! -e "$HOME_ROOT/.agents/skills/codex-only"
test -f "$HOME_ROOT/.agents/skills/ghost/SKILL.md"

# A renamed upstream leaves no stale marked copy.
mv "$FIXTURE/other-skills/alpha/still-applies" \
  "$FIXTURE/other-skills/alpha/still-applies-renamed"
perl -0pi -e 's/`still-applies`/`still-applies-renamed`/' \
  "$FIXTURE/agent-tooling/skills-matrix.md"
set +e
run_distribute --json > "$FIXTURE/renamed.json"
renamed_exit=$?
set -e
test "$renamed_exit" -eq 1
test ! -e "$HOME_ROOT/.claude/skills/still-applies"
test ! -e "$HOME_ROOT/.agents/skills/still-applies"
test -f "$HOME_ROOT/.claude/skills/still-applies-renamed/SKILL.md"
test -f "$HOME_ROOT/.agents/skills/still-applies-renamed/SKILL.md"

# A live lock blocks the command; a dead lock is recovered.
LOCK="$RUNTIME/agent-scripts-skill-topology-$(id -u).lock"
mkdir "$LOCK"
printf '%s\n' "$$" > "$LOCK/pid"
set +e
run_distribute --json > "$FIXTURE/locked.json"
locked_exit=$?
set -e
test "$locked_exit" -eq 1
jq -e 'any(.errors[]; contains("already running"))' "$FIXTURE/locked.json" >/dev/null
rm -rf "$LOCK"
mkdir "$LOCK"
printf '%s\n' 99999999 > "$LOCK/pid"
set +e
run_distribute --json > "$FIXTURE/recovered.json"
recovered_exit=$?
set -e
test "$recovered_exit" -eq 1
jq -e 'any(.warnings[]; .message | contains("recovered stale topology lock"))' \
  "$FIXTURE/recovered.json" >/dev/null

# Symlinked surface entries are refused before any reconciliation writes.
mkdir -p "$HOME_ROOT/entry-target"
ln -s "$HOME_ROOT/entry-target" "$HOME_ROOT/.claude/skills/linked-skill"
claude_hash="$(shasum -a 256 "$HOME_ROOT/.claude/skills/repo-both/SKILL.md" | cut -d' ' -f1)"
set +e
run_distribute --json > "$FIXTURE/symlink-entry.json"
symlink_entry_exit=$?
set -e
test "$symlink_entry_exit" -eq 1
jq -e 'any(.errors[]; contains("symlinked skill surface entry"))' \
  "$FIXTURE/symlink-entry.json" >/dev/null
test "$(shasum -a 256 "$HOME_ROOT/.claude/skills/repo-both/SKILL.md" | cut -d' ' -f1)" = "$claude_hash"
rm "$HOME_ROOT/.claude/skills/linked-skill"

# Surface-root symlinks are refused before any reconciliation writes.
rm -rf "$HOME_ROOT/.agents/skills"
mkdir -p "$HOME_ROOT/symlink-target"
ln -s "$HOME_ROOT/symlink-target" "$HOME_ROOT/.agents/skills"
claude_hash="$(shasum -a 256 "$HOME_ROOT/.claude/skills/repo-both/SKILL.md" | cut -d' ' -f1)"
set +e
run_distribute --json > "$FIXTURE/symlink.json"
symlink_exit=$?
set -e
test "$symlink_exit" -eq 1
jq -e 'any(.errors[]; contains("symlinked skill surface root"))' "$FIXTURE/symlink.json" >/dev/null
test "$(shasum -a 256 "$HOME_ROOT/.claude/skills/repo-both/SKILL.md" | cut -d' ' -f1)" = "$claude_hash"

echo "sync-skill-surfaces matrix distribute tests passed"
