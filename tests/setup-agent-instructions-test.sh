#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

test ! -e "$REPO_ROOT/agent-tooling/sync-skills"

FIXTURE="$TMP_ROOT/repo"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/rules" "$HOME_DIR"
cp "$REPO_ROOT/agent-tooling/setup-agent-instructions.sh" \
   "$REPO_ROOT/agent-tooling/build-codex-instructions.sh" "$FIXTURE/agent-tooling/"
printf 'shared rules\n' > "$FIXTURE/AGENTS.MD"
printf 'topic rules\n' > "$FIXTURE/rules/topic.md"

setup() { HOME="$HOME_DIR" "$FIXTURE/agent-tooling/setup-agent-instructions.sh"; }
build() { "$FIXTURE/agent-tooling/build-codex-instructions.sh" "$@"; }

# Setup refuses to run before the Codex artifact is built.
if setup >/dev/null 2>&1; then
  echo "expected setup to fail without AGENTS.codex.md" >&2
  exit 1
fi

build > "$TMP_ROOT/build.out"
grep -Fx 'shared rules' "$FIXTURE/AGENTS.codex.md" >/dev/null
grep -Fx 'topic rules' "$FIXTURE/AGENTS.codex.md" >/dev/null
build --check >/dev/null

# A source rule change makes the tracked artifact stale, and --check fails loudly.
printf 'topic rules v2\n' > "$FIXTURE/rules/topic.md"
if build --check >/dev/null 2>&1; then
  echo "expected --check to fail on stale artifact" >&2
  exit 1
fi
build >/dev/null
grep -Fx 'topic rules v2' "$FIXTURE/AGENTS.codex.md" >/dev/null

setup > "$TMP_ROOT/first.out" 2> "$TMP_ROOT/first.err"
test ! -s "$TMP_ROOT/first.err"
for pointer in "$HOME_DIR/.claude/CLAUDE.md" "$HOME_DIR/.claude/AGENTS.md"; do
  test -L "$pointer"
  test "$(readlink "$pointer")" = "$FIXTURE/AGENTS.MD"
done
test "$(readlink "$HOME_DIR/.claude/rules/topic.md")" = "$FIXTURE/rules/topic.md"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$FIXTURE/AGENTS.codex.md"
grep -F "linked $HOME_DIR/.claude/CLAUDE.md -> $FIXTURE/AGENTS.MD" "$TMP_ROOT/first.out" >/dev/null

# The Codex pointer is a symlink, so a repository update refreshes it with no
# separate install step. This is the staleness guard.
printf 'topic rules v3\n' > "$FIXTURE/rules/topic.md"
build >/dev/null
grep -Fx 'topic rules v3' "$HOME_DIR/.codex/AGENTS.md" >/dev/null

setup > "$TMP_ROOT/second.out" 2> "$TMP_ROOT/second.err"
test ! -s "$TMP_ROOT/second.err"
grep -Fx 'instruction pointers up to date' "$TMP_ROOT/second.out" >/dev/null

# Real files and foreign symlinks are user-owned. Preserve both, on every
# pointer including the Codex one. A missing owned path stays independently
# repairable.
rm "$HOME_DIR/.claude/CLAUDE.md" "$HOME_DIR/.claude/AGENTS.md" "$HOME_DIR/.codex/AGENTS.md"
printf 'user rules\n' > "$HOME_DIR/.claude/CLAUDE.md"
ln -s "$HOME_DIR/custom-agents.md" "$HOME_DIR/.claude/AGENTS.md"
ln -s "$HOME_DIR/custom-codex.md" "$HOME_DIR/.codex/AGENTS.md"
printf 'user codex rules\n' > "$HOME_DIR/custom-codex.md"
setup > "$TMP_ROOT/preserve.out" 2> "$TMP_ROOT/preserve.err"
test "$(cat "$HOME_DIR/.claude/CLAUDE.md")" = "user rules"
test "$(readlink "$HOME_DIR/.claude/AGENTS.md")" = "$HOME_DIR/custom-agents.md"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$HOME_DIR/custom-codex.md"
grep -F "preserving real file: $HOME_DIR/.claude/CLAUDE.md" "$TMP_ROOT/preserve.err" >/dev/null
grep -F "preserving foreign symlink: $HOME_DIR/.claude/AGENTS.md" "$TMP_ROOT/preserve.err" >/dev/null
grep -F "preserving foreign symlink: $HOME_DIR/.codex/AGENTS.md" "$TMP_ROOT/preserve.err" >/dev/null

# An unrelated user rule already in ~/.claude/rules survives.
printf 'user note\n' > "$HOME_DIR/.claude/rules/personal.md"
setup > /dev/null 2>&1
test "$(cat "$HOME_DIR/.claude/rules/personal.md")" = "user note"

# A dangling foreign symlink fails -e but is still user state.
rm "$HOME_DIR/.codex/AGENTS.md"
ln -s "$HOME_DIR/gone.md" "$HOME_DIR/.codex/AGENTS.md"
setup > "$TMP_ROOT/dangling.out" 2> "$TMP_ROOT/dangling.err"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$HOME_DIR/gone.md"
grep -F "preserving foreign symlink: $HOME_DIR/.codex/AGENTS.md" "$TMP_ROOT/dangling.err" >/dev/null

# The tracked artifact in this repository must match its sources.
"$REPO_ROOT/agent-tooling/build-codex-instructions.sh" --check >/dev/null

# No committed instruction file may carry a personal identifier or a
# machine-specific path. Plain `!` would skip errexit and never fail (SC2251).
if rg -n '/Users/|/home/[a-z]' "$REPO_ROOT/AGENTS.MD" "$REPO_ROOT/AGENTS.codex.md" "$REPO_ROOT"/rules/*.md; then
  echo "machine-specific path in a tracked instruction file" >&2
  exit 1
fi

echo "agent instruction setup tests passed"
