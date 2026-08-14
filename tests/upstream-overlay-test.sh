#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

UPSTREAM_REPO="$TMP_ROOT/upstream"
LOCAL_REPO="$TMP_ROOT/local"

git init -q -b main "$UPSTREAM_REPO"
git -C "$UPSTREAM_REPO" config user.name Test
git -C "$UPSTREAM_REPO" config user.email test@example.com
mkdir -p "$UPSTREAM_REPO/scripts"
printf 'upstream shared\n' > "$UPSTREAM_REPO/shared.txt"
printf 'upstream tool\n' > "$UPSTREAM_REPO/scripts/tool"
git -C "$UPSTREAM_REPO" add .
git -C "$UPSTREAM_REPO" commit -qm 'initial upstream'

git clone -q "$UPSTREAM_REPO" "$LOCAL_REPO"
git -C "$LOCAL_REPO" config user.name Test
git -C "$LOCAL_REPO" config user.email test@example.com
mkdir -p "$LOCAL_REPO/agent-tooling"
cp "$REPO_ROOT/agent-tooling/sync-upstream-overlay.sh" "$LOCAL_REPO/agent-tooling/"
printf 'local shared change\n' > "$LOCAL_REPO/shared.txt"
printf 'local only\n' > "$LOCAL_REPO/local.txt"
git -C "$LOCAL_REPO" rm -q scripts/tool
git -C "$LOCAL_REPO" add .
git -C "$LOCAL_REPO" commit -qm 'local overlay changes'

AGENT_SCRIPTS_UPSTREAM_URL="$UPSTREAM_REPO" \
  "$LOCAL_REPO/agent-tooling/sync-upstream-overlay.sh" > "$TMP_ROOT/sync.out"
test -f "$LOCAL_REPO/scripts/tool"
grep -Fx 'local shared change' "$LOCAL_REPO/shared.txt" >/dev/null
grep -Fx 'local only' "$LOCAL_REPO/local.txt" >/dev/null
grep -F 'Restored 1 missing upstream path(s).' "$TMP_ROOT/sync.out" >/dev/null
AGENT_SCRIPTS_UPSTREAM_URL="$UPSTREAM_REPO" \
  "$LOCAL_REPO/agent-tooling/sync-upstream-overlay.sh" --check > "$TMP_ROOT/check.out"
grep -F 'Upstream overlay complete' "$TMP_ROOT/check.out" >/dev/null

git -C "$LOCAL_REPO" add .
git -C "$LOCAL_REPO" commit -qm 'restore overlay'
rm "$LOCAL_REPO/scripts/tool"
if "$LOCAL_REPO/agent-tooling/sync-upstream-overlay.sh" --check \
    > "$TMP_ROOT/missing.out" 2>&1; then
  echo 'FAIL: overlay check accepted a missing upstream path' >&2
  exit 1
fi
grep -F 'scripts/tool' "$TMP_ROOT/missing.out" >/dev/null
git -C "$LOCAL_REPO" checkout -q -- scripts/tool

printf 'new upstream path\n' > "$UPSTREAM_REPO/scripts/new-tool"
git -C "$UPSTREAM_REPO" add scripts/new-tool
git -C "$UPSTREAM_REPO" commit -qm 'add upstream path'
AGENT_SCRIPTS_UPSTREAM_URL="$UPSTREAM_REPO" \
  "$LOCAL_REPO/agent-tooling/sync-upstream-overlay.sh" > "$TMP_ROOT/resync.out"
test -f "$LOCAL_REPO/scripts/new-tool"
grep -Fx 'local shared change' "$LOCAL_REPO/shared.txt" >/dev/null
test "$(jq -r .commit "$LOCAL_REPO/agent-tooling/upstream-overlay.json")" \
  = "$(git -C "$UPSTREAM_REPO" rev-parse HEAD)"

echo 'upstream overlay tests passed'
