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

UPDATERS=(update-agents.sh update-skill-topology.sh generate-skills-matrix.py sync-skill-surfaces.sh)

for updater in "${UPDATERS[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    > "$SCRIPTS/$updater"
  chmod +x "$SCRIPTS/$updater"
done

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

echo "update-all tests passed"
