#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

test ! -e "$REPO_ROOT/scripts/sync-skills"

FIXTURE="$TMP_ROOT/repo"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$FIXTURE/scripts" "$HOME_DIR"
cp "$REPO_ROOT/scripts/setup-agent-instructions.sh" "$FIXTURE/scripts/"
printf 'shared rules\n' > "$FIXTURE/AGENTS.MD"

HOME="$HOME_DIR" "$FIXTURE/scripts/setup-agent-instructions.sh" > "$TMP_ROOT/first.out" 2> "$TMP_ROOT/first.err"
test ! -s "$TMP_ROOT/first.err"
for pointer in \
  "$HOME_DIR/.claude/CLAUDE.md" \
  "$HOME_DIR/.claude/AGENTS.md" \
  "$HOME_DIR/.codex/AGENTS.md"; do
  test -L "$pointer"
  test "$(readlink "$pointer")" = "$FIXTURE/AGENTS.MD"
done
grep -F "linked $HOME_DIR/.claude/CLAUDE.md -> $FIXTURE/AGENTS.MD" "$TMP_ROOT/first.out" >/dev/null

HOME="$HOME_DIR" "$FIXTURE/scripts/setup-agent-instructions.sh" > "$TMP_ROOT/second.out" 2> "$TMP_ROOT/second.err"
test ! -s "$TMP_ROOT/second.err"
grep -Fx 'instruction pointers up to date' "$TMP_ROOT/second.out" >/dev/null

# Real files and foreign symlinks are user-owned. Preserve both. A missing
# owned path remains independently repairable.
rm "$HOME_DIR/.claude/CLAUDE.md" "$HOME_DIR/.claude/AGENTS.md" "$HOME_DIR/.codex/AGENTS.md"
printf 'user rules\n' > "$HOME_DIR/.claude/CLAUDE.md"
ln -s "$HOME_DIR/custom-agents.md" "$HOME_DIR/.claude/AGENTS.md"
HOME="$HOME_DIR" "$FIXTURE/scripts/setup-agent-instructions.sh" > "$TMP_ROOT/preserve.out" 2> "$TMP_ROOT/preserve.err"
test "$(cat "$HOME_DIR/.claude/CLAUDE.md")" = "user rules"
test "$(readlink "$HOME_DIR/.claude/AGENTS.md")" = "$HOME_DIR/custom-agents.md"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$FIXTURE/AGENTS.MD"
grep -F "preserving real file: $HOME_DIR/.claude/CLAUDE.md" "$TMP_ROOT/preserve.err" >/dev/null
grep -F "preserving foreign symlink: $HOME_DIR/.claude/AGENTS.md" "$TMP_ROOT/preserve.err" >/dev/null

echo "agent instruction setup tests passed"
