#!/usr/bin/env bash
set -euo pipefail

# Black-box contract: routine updates have four ordered steps and still
# attempt all, summarize all, and aggregate failure.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPTS="$TMPDIR/scripts"
UPDATE_LOG="$TMPDIR/update.log"
mkdir -p "$SCRIPTS"
cp "$REPO_ROOT/agent-tooling/update-all.sh" "$SCRIPTS/"

UPDATERS=(update-agents.sh update-skill-topology.sh generate-skills-matrix.sh sync-skill-surfaces.sh)

for updater in "${UPDATERS[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    > "$SCRIPTS/$updater"
  chmod +x "$SCRIPTS/$updater"
done

UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --help > "$TMPDIR/help.out"
rg -F 'Usage: update-all.sh [--ship]' "$TMPDIR/help.out" >/dev/null
test ! -e "$UPDATE_LOG"
UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --unknown --help \
  > "$TMPDIR/help-with-invalid.out"
rg -F 'Usage: update-all.sh [--ship]' "$TMPDIR/help-with-invalid.out" >/dev/null
test ! -e "$UPDATE_LOG"

set +e
UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --unknown \
  > "$TMPDIR/invalid.out" 2>&1
invalid_code=$?
set -e
test "$invalid_code" -eq 2
rg -F 'unknown option: --unknown' "$TMPDIR/invalid.out" >/dev/null
test ! -e "$UPDATE_LOG"

UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" > "$TMPDIR/out" 2>&1

printf '%s\n' "${UPDATERS[@]}" > "$TMPDIR/expected.log"
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"

grep -F 'agent CLIs' "$TMPDIR/out" >/dev/null
grep -F 'skill acquire' "$TMPDIR/out" >/dev/null
grep -F 'skills matrix' "$TMPDIR/out" >/dev/null
grep -F 'skill distribute' "$TMPDIR/out" >/dev/null

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
  'exit 17' \
  > "$SCRIPTS/update-agents.sh"
chmod +x "$SCRIPTS/update-agents.sh"
: > "$UPDATE_LOG"

if UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" > "$TMPDIR/failure.out" 2>&1; then
  echo "FAIL: routine updater ignored a failed step" >&2
  exit 1
fi
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
grep -F 'agent CLIs' "$TMPDIR/failure.out" >/dev/null
grep -F 'skill acquire' "$TMPDIR/failure.out" >/dev/null
grep -F 'skills matrix' "$TMPDIR/failure.out" >/dev/null
grep -F 'skill distribute' "$TMPDIR/failure.out" >/dev/null

GIT_BIN="$TMPDIR/git-bin"
GIT_LOG="$TMPDIR/git.log"
GIT_PULL_MARKER="$TMPDIR/git-pulled"
GIT_ADD_MARKER="$TMPDIR/git-added"
GIT_COMMIT_MARKER="$TMPDIR/git-committed"
SHIP_LOG="$TMPDIR/ship.log"
mkdir -p "$GIT_BIN" "$TMPDIR/other-skills/test"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  '[ "$1" = "-C" ]' \
  'shift 2' \
  'printf '\''%s\n'\'' "$*" >> "$GIT_LOG"' \
  'case "${1:-}" in' \
  '  rev-parse)' \
  '    [ "${2:-}" = "--is-inside-work-tree" ] && echo true' \
  '    ;;' \
  '  status)' \
  '    if [ "${2:-}" = "--porcelain" ]; then' \
  '      if [ "${GIT_DIRTY:-0}" -eq 1 ]; then' \
  '        echo " M existing-user-change"' \
  '      elif [ -e "$GIT_PULL_MARKER" ] && [ ! -e "$GIT_COMMIT_MARKER" ]; then' \
  '        echo " M other-skills/test/.source.json"' \
  '      fi' \
  '    elif [ "${2:-}" = "-sb" ]; then' \
  '      echo "## main...origin/main"' \
  '    fi' \
  '    ;;' \
  '  pull)' \
  '    [ "${2:-}" = "--ff-only" ]' \
  '    touch "$GIT_PULL_MARKER"' \
  '    ;;' \
  '  diff)' \
  '    if [ "${2:-}" = "--name-only" ]; then' \
  '      echo "other-skills/test/.source.json"' \
  '    elif [ "${2:-}" = "--cached" ] && [ "${3:-}" = "--quiet" ]; then' \
  '      [ ! -e "$GIT_ADD_MARKER" ]' \
  '    fi' \
  '    ;;' \
  '  add)' \
  '    [ "${2:-}" = "-A" ]' \
  '    touch "$GIT_ADD_MARKER"' \
  '    ;;' \
  '  commit)' \
  '    [ "${2:-}" = "-m" ]' \
  '    [ "${3:-}" = "chore: refresh staged skills" ]' \
  '    touch "$GIT_COMMIT_MARKER"' \
  '    ;;' \
  '  push)' \
  '    [ -e "$GIT_COMMIT_MARKER" ]' \
  '    ;;' \
  '  *) exit 97 ;;' \
  'esac' \
  > "$GIT_BIN/git"
chmod +x "$GIT_BIN/git"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''verify\n'\'' >> "$SHIP_LOG"' \
  > "$SCRIPTS/verify.sh"
chmod +x "$SCRIPTS/verify.sh"

printf '%s\n' \
  '---' \
  'summary: Test changelog.' \
  '---' \
  '' \
  '# Changelog' \
  '' \
  '## Unreleased' \
  '' \
  '- Existing entry.' \
  > "$TMPDIR/CHANGELOG.md"
printf '%s\n' \
  '{' \
  '  "repo": "example/test",' \
  '  "commit": "abcdef1234567890",' \
  '  "syncedAt": "2026-08-14T00:00:00Z"' \
  '}' \
  > "$TMPDIR/other-skills/test/.source.json"

: > "$UPDATE_LOG"
set +e
PATH="$GIT_BIN:$PATH" \
  GIT_DIRTY=1 \
  GIT_LOG="$GIT_LOG" \
  GIT_PULL_MARKER="$GIT_PULL_MARKER" \
  GIT_ADD_MARKER="$GIT_ADD_MARKER" \
  GIT_COMMIT_MARKER="$GIT_COMMIT_MARKER" \
  UPDATE_LOG="$UPDATE_LOG" \
  "$SCRIPTS/update-all.sh" --ship > "$TMPDIR/dirty-ship.out" 2>&1
dirty_ship_code=$?
set -e
test "$dirty_ship_code" -eq 1
test ! -s "$UPDATE_LOG"
rg -F -- '--ship requires a clean worktree' "$TMPDIR/dirty-ship.out" >/dev/null

for updater in "${UPDATERS[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    > "$SCRIPTS/$updater"
  chmod +x "$SCRIPTS/$updater"
done

: > "$UPDATE_LOG"
: > "$GIT_LOG"
rm -f "$GIT_PULL_MARKER" "$GIT_ADD_MARKER" "$GIT_COMMIT_MARKER"
PATH="$GIT_BIN:$PATH" \
  GIT_LOG="$GIT_LOG" \
  GIT_PULL_MARKER="$GIT_PULL_MARKER" \
  GIT_ADD_MARKER="$GIT_ADD_MARKER" \
  GIT_COMMIT_MARKER="$GIT_COMMIT_MARKER" \
  SHIP_LOG="$SHIP_LOG" \
  UPDATE_LOG="$UPDATE_LOG" \
  "$SCRIPTS/update-all.sh" --ship > "$TMPDIR/ship.out" 2>&1

cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
rg -Fx 'verify' "$SHIP_LOG" >/dev/null
rg -F 'pull --ff-only' "$GIT_LOG" >/dev/null
rg -Fx 'commit -m chore: refresh staged skills' "$GIT_LOG" >/dev/null
rg -Fx 'push' "$GIT_LOG" >/dev/null
rg -F 'test abcdef1' "$TMPDIR/CHANGELOG.md" >/dev/null
rg -F '## main...origin/main' "$TMPDIR/ship.out" >/dev/null

echo "update-all tests passed"
