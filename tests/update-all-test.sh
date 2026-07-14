#!/usr/bin/env bash
set -euo pipefail

# Black-box contract: routine updates cannot bypass manifest policy through
# bulk repo publication or generic/direct plugin update entrypoints.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPTS="$TMPDIR/scripts"
UPDATE_LOG="$TMPDIR/update.log"
mkdir -p "$SCRIPTS"
cp "$REPO_ROOT/scripts/update-all.sh" "$SCRIPTS/"

UPDATERS=(
  update-agents.sh
  update-cli-skills.sh
  update-visual-explainer.sh
  update-khazix-skills.sh
  update-anthropic-skills.sh
  update-mattpocock-skills.sh
)

for updater in "${UPDATERS[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    > "$SCRIPTS/$updater"
  chmod +x "$SCRIPTS/$updater"
done

FORBIDDEN_UPDATERS=(
  update-repo-skills.sh
  update-cc-plugins.sh
  update-claude-mem.sh
  update-waza.sh
)
for updater in "${FORBIDDEN_UPDATERS[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''forbidden updater: %s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    'exit 99' \
    > "$SCRIPTS/$updater"
  chmod +x "$SCRIPTS/$updater"
done

UPDATE_LOG="$UPDATE_LOG" "$SCRIPTS/update-all.sh" > "$TMPDIR/out" 2>&1

printf '%s\n' "${UPDATERS[@]}" > "$TMPDIR/expected.log"
cmp "$TMPDIR/expected.log" "$UPDATE_LOG"

if grep -F 'repo-skills' "$TMPDIR/out" >/dev/null; then
  echo "FAIL: routine updater invoked or reported repo-skills sync" >&2
  exit 1
fi

echo "update-all tests passed"
