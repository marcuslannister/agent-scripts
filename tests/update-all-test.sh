#!/usr/bin/env bash
set -euo pipefail

# Black-box contract (ADR-0009): the main-machine updater has five ordered
# steps, attempts all of them, summarizes all, aggregates failure except the
# best-effort plugin refresh, and ships by default. --no-ship updates only.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPTS="$TMPDIR/scripts"
UPDATE_LOG="$TMPDIR/update.log"
mkdir -p "$SCRIPTS"
cp "$REPO_ROOT/agent-tooling/update-all.sh" "$SCRIPTS/"

UPDATERS=(update-agents.sh update-plugins.sh update-skill-topology.sh \
  generate-skills-matrix.sh sync-skill-surfaces.sh)

write_updaters() {
  local updater
  for updater in "${UPDATERS[@]}"; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
      > "$SCRIPTS/$updater"
    chmod +x "$SCRIPTS/$updater"
  done
}
write_updaters
printf '%s\n' "${UPDATERS[@]}" > "$TMPDIR/expected.log"

UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --help > "$TMPDIR/help.out"
rg -F 'Usage: update-all.sh [--no-ship]' "$TMPDIR/help.out" >/dev/null
test ! -e "$UPDATE_LOG"

set +e
UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --unknown > "$TMPDIR/invalid.out" 2>&1
invalid_code=$?
set -e
test "$invalid_code" -eq 2
rg -F 'unknown option: --unknown' "$TMPDIR/invalid.out" >/dev/null
test ! -e "$UPDATE_LOG"

# --no-ship: every step runs, nothing is committed.
UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --no-ship > "$TMPDIR/out" 2>&1
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
for label in 'agent CLIs' 'native plugins' 'skill acquire' 'skills matrix' 'skill distribute'; do
  grep -F "$label" "$TMPDIR/out" >/dev/null
done

# A failed plugin refresh is reported but never fails the run (ADR-0009).
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
  'exit 9' \
  > "$SCRIPTS/update-plugins.sh"
chmod +x "$SCRIPTS/update-plugins.sh"
: > "$UPDATE_LOG"
UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --no-ship > "$TMPDIR/plugin-fail.out" 2>&1
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
rg '✗.*native plugins' "$TMPDIR/plugin-fail.out" >/dev/null
write_updaters

# A failed step still lets the others run, and the run exits non-zero.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
  'exit 17' \
  > "$SCRIPTS/update-agents.sh"
chmod +x "$SCRIPTS/update-agents.sh"
: > "$UPDATE_LOG"
if UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" --no-ship > "$TMPDIR/failure.out" 2>&1; then
  echo "FAIL: routine updater ignored a failed step" >&2
  exit 1
fi
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"

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

# A dirty worktree stops the default ship before any update runs.
write_updaters
: > "$UPDATE_LOG"
set +e
PATH="$GIT_BIN:$PATH" \
  GIT_DIRTY=1 \
  GIT_LOG="$GIT_LOG" \
  GIT_PULL_MARKER="$GIT_PULL_MARKER" \
  GIT_ADD_MARKER="$GIT_ADD_MARKER" \
  GIT_COMMIT_MARKER="$GIT_COMMIT_MARKER" \
  UPDATE_LOG="$UPDATE_LOG" \
  "$SCRIPTS/update-all.sh" > "$TMPDIR/dirty-ship.out" 2>&1
dirty_ship_code=$?
set -e
test "$dirty_ship_code" -eq 1
test ! -s "$UPDATE_LOG"
rg -F 'ship requires a clean worktree' "$TMPDIR/dirty-ship.out" >/dev/null

# Default run ships: pull, update, verify, changelog, commit, push.
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
  "$SCRIPTS/update-all.sh" > "$TMPDIR/ship.out" 2>&1

cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
rg -Fx 'verify' "$SHIP_LOG" >/dev/null
rg -F 'pull --ff-only' "$GIT_LOG" >/dev/null
rg -Fx 'commit -m chore: refresh staged skills' "$GIT_LOG" >/dev/null
rg -Fx 'push' "$GIT_LOG" >/dev/null
rg -F 'test abcdef1' "$TMPDIR/CHANGELOG.md" >/dev/null
rg -F '## main...origin/main' "$TMPDIR/ship.out" >/dev/null

# --no-ship leaves git alone entirely.
: > "$UPDATE_LOG"
: > "$GIT_LOG"
PATH="$GIT_BIN:$PATH" \
  GIT_LOG="$GIT_LOG" \
  GIT_PULL_MARKER="$GIT_PULL_MARKER" \
  GIT_ADD_MARKER="$GIT_ADD_MARKER" \
  GIT_COMMIT_MARKER="$GIT_COMMIT_MARKER" \
  UPDATE_LOG="$UPDATE_LOG" \
  "$SCRIPTS/update-all.sh" --no-ship > "$TMPDIR/noship.out" 2>&1
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"
test ! -s "$GIT_LOG"

echo "update-all tests passed"
