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

# A failed build never touches the tracked artifact, and --check never goes
# green on partial output. Root ignores the permission bit, so skip there.
if [ "$(id -u)" -ne 0 ]; then
  cp "$FIXTURE/AGENTS.codex.md" "$TMP_ROOT/good.codex.md"
  chmod 000 "$FIXTURE/rules/topic.md"
  if build > /dev/null 2> "$TMP_ROOT/failbuild.err"; then
    echo "expected build to fail on an unreadable rule file" >&2
    exit 1
  fi
  grep -F 'left unchanged' "$TMP_ROOT/failbuild.err" >/dev/null
  cmp -s "$FIXTURE/AGENTS.codex.md" "$TMP_ROOT/good.codex.md"
  if build --check >/dev/null 2>&1; then
    echo "expected --check to fail when the build fails" >&2
    exit 1
  fi
  chmod 644 "$FIXTURE/rules/topic.md"
  build --check >/dev/null
fi

setup > "$TMP_ROOT/first.out" 2> "$TMP_ROOT/first.err"
test ! -s "$TMP_ROOT/first.err"
test -L "$HOME_DIR/.claude/CLAUDE.md"
test "$(readlink "$HOME_DIR/.claude/CLAUDE.md")" = "$FIXTURE/AGENTS.MD"
# Setup does not own ~/.claude/AGENTS.md; Claude Code reads CLAUDE.md.
test ! -e "$HOME_DIR/.claude/AGENTS.md"
test "$(readlink "$HOME_DIR/.claude/rules")" = "$FIXTURE/rules"
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
rm "$HOME_DIR/.claude/CLAUDE.md" "$HOME_DIR/.codex/AGENTS.md"
printf 'user rules\n' > "$HOME_DIR/.claude/CLAUDE.md"
ln -s "$HOME_DIR/custom-codex.md" "$HOME_DIR/.codex/AGENTS.md"
printf 'user codex rules\n' > "$HOME_DIR/custom-codex.md"
setup > "$TMP_ROOT/preserve.out" 2> "$TMP_ROOT/preserve.err"
test "$(cat "$HOME_DIR/.claude/CLAUDE.md")" = "user rules"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$HOME_DIR/custom-codex.md"
grep -F "preserving real file: $HOME_DIR/.claude/CLAUDE.md" "$TMP_ROOT/preserve.err" >/dev/null
grep -F "preserving foreign symlink: $HOME_DIR/.codex/AGENTS.md" "$TMP_ROOT/preserve.err" >/dev/null

# A relative symlink to the same place is ours, not foreign: no warning, no churn.
rm "$HOME_DIR/.claude/rules"
ln -s "../../repo/rules" "$HOME_DIR/.claude/rules"
setup > "$TMP_ROOT/relative.out" 2> "$TMP_ROOT/relative.err"
# Other pointers are foreign by now and warn legitimately, so assert only that
# the rules pointer is not among them.
if grep -F "preserving foreign symlink: $HOME_DIR/.claude/rules" "$TMP_ROOT/relative.err"; then
  echo "an equivalent relative symlink was treated as foreign" >&2
  exit 1
fi
test "$(readlink "$HOME_DIR/.claude/rules")" = "../../repo/rules"
grep -Fx 'topic rules v3' "$HOME_DIR/.claude/rules/topic.md" >/dev/null

# Predecessor 1: an existing machine has the Codex pointer symlinked to
# AGENTS.MD. That is installer-owned, so it migrates to the generated file.
rm -f "$HOME_DIR/.codex/AGENTS.md"
ln -s "$FIXTURE/AGENTS.MD" "$HOME_DIR/.codex/AGENTS.md"
setup > "$TMP_ROOT/legacy.out" 2>/dev/null
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$FIXTURE/AGENTS.codex.md"
grep -F 'migrated legacy Codex symlink' "$TMP_ROOT/legacy.out" >/dev/null

# A regular file is never deleted, whatever it holds. Even a byte-identical
# copy of the generated file stays put, because nothing proves we wrote it.
rm -f "$HOME_DIR/.codex/AGENTS.md"
cp "$FIXTURE/AGENTS.codex.md" "$HOME_DIR/.codex/AGENTS.md"
setup > /dev/null 2> "$TMP_ROOT/regular.err"
test ! -L "$HOME_DIR/.codex/AGENTS.md"
cmp -s "$HOME_DIR/.codex/AGENTS.md" "$FIXTURE/AGENTS.codex.md"
grep -F 'may be reading stale rules' "$TMP_ROOT/regular.err" >/dev/null

printf 'my own codex rules\n' > "$HOME_DIR/.codex/AGENTS.md"
setup > /dev/null 2> "$TMP_ROOT/unknown.err"
test "$(cat "$HOME_DIR/.codex/AGENTS.md")" = "my own codex rules"
grep -F 'may be reading stale rules' "$TMP_ROOT/unknown.err" >/dev/null
rm -f "$HOME_DIR/.codex/AGENTS.md"
setup >/dev/null 2>&1

# A dangling foreign symlink fails -e but is still user state.
rm "$HOME_DIR/.codex/AGENTS.md"
ln -s "$HOME_DIR/gone.md" "$HOME_DIR/.codex/AGENTS.md"
setup > "$TMP_ROOT/dangling.out" 2> "$TMP_ROOT/dangling.err"
test "$(readlink "$HOME_DIR/.codex/AGENTS.md")" = "$HOME_DIR/gone.md"
grep -F "preserving foreign symlink: $HOME_DIR/.codex/AGENTS.md" "$TMP_ROOT/dangling.err" >/dev/null

# The tracked artifact in this repository must match its sources.
"$REPO_ROOT/agent-tooling/build-codex-instructions.sh" --check >/dev/null

# Every topic link must be home-relative. A repo-relative link resolves against
# the agent's cwd, so it silently breaks in every project except this one.
links="$(rg -o --replace '$1' '^- \[[^]]+\]\(([^)]+)\)' "$REPO_ROOT/AGENTS.MD")"
test -n "$links"
while read -r link; do
  # shellcheck disable=SC2088  # matching the literal ~ in the link, not expanding it
  case "$link" in
    '~/.claude/rules/'*) ;;
    *) echo "topic link is not home-relative: $link" >&2; exit 1 ;;
  esac
done <<< "$links"

# The links must resolve from a cwd outside this repository, which is where an
# agent almost always runs. Resolve them against the fixture HOME.
mkdir -p "$TMP_ROOT/elsewhere"
(
  cd "$TMP_ROOT/elsewhere"
  test ! -e rules/topic.md
  test -r "$HOME_DIR/.claude/rules/topic.md"
  grep -Fx 'topic rules v3' "$HOME_DIR/.claude/rules/topic.md" >/dev/null
)

# No committed instruction file may carry a personal identifier or a
# machine-specific path. Plain `!` would skip errexit and never fail (SC2251).
if rg -n '/Users/|/home/[a-z]' "$REPO_ROOT/AGENTS.MD" "$REPO_ROOT/AGENTS.codex.md" "$REPO_ROOT"/rules/*.md; then
  echo "machine-specific path in a tracked instruction file" >&2
  exit 1
fi

echo "agent instruction setup tests passed"
