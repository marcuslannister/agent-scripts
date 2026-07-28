#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

COMMAND="$REPO_ROOT/agent-tooling/distribution-topology/codex-root-hygiene.sh"
HOME_ROOT="$TMP_ROOT/home"
mkdir -p "$HOME_ROOT/.agents/skills"

test -z "$("$COMMAND" inspect "$HOME_ROOT")"
"$COMMAND" reconcile "$HOME_ROOT"
"$COMMAND" verify "$HOME_ROOT"

rm -rf "$HOME_ROOT/.agents/skills"
mkdir -p "$HOME_ROOT/target"
printf '%s\n' keep > "$HOME_ROOT/target/keep.txt"
ln -s "$HOME_ROOT/target" "$HOME_ROOT/.agents/skills"
test "$("$COMMAND" inspect "$HOME_ROOT")" = root-symlink
if "$COMMAND" reconcile "$HOME_ROOT" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"; then
  echo 'Codex root guard accepted a symlinked surface' >&2
  exit 1
fi
rg -F 'refusing symlinked skill surface root' "$TMP_ROOT/err" >/dev/null
test -f "$HOME_ROOT/target/keep.txt"
test -L "$HOME_ROOT/.agents/skills"

echo "Codex root symlink guard tests passed"
