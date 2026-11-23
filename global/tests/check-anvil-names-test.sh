#!/usr/bin/env bash
# check-anvil-names must reject the stale names this repo once shipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SKILL="$TMP_ROOT/skills/anvil-advanced-ops/SKILL.md"
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/rules" "$(dirname "$SKILL")"
printf '%s\n' mcp__anvil__emacs-eval mcp__anvil__emacs-eval-async \
  mcp__anvil-emacs-eval__cron-list mcp__anvil-emacs-eval__git-status \
  > "$TMP_ROOT/bin/anvil-tools.txt"
: > "$TMP_ROOT/AGENTS.md"

run() { ANVIL_NAMES_ROOT="$TMP_ROOT" "$REPO_ROOT/bin/check-anvil-names" >/dev/null 2>&1; }
expect() { # expect <pass|fail> <label>
  if run; then got=pass; else got=fail; fi
  [ "$got" = "$1" ] || { echo "FAIL check-anvil-names: expected $1 for $2" >&2; exit 1; }
}

printf 'Use `mcp__anvil-emacs-eval__git-status` and `mcp__anvil__emacs-eval*`, not `mcp__codegraph__codegraph_explore`.\n' > "$TMP_ROOT/rules/tooling.md"
printf -- '- `cron-list`\n- `emacs-eval*`\n- `anvil-cron` tasks\n' > "$SKILL"
expect pass "registered names"

printf 'Eval tools live under `mcp__anvil-eval__`.\n' > "$TMP_ROOT/rules/tooling.md"
expect fail "an unknown MCP prefix"

printf 'Use `mcp__anvil-emacs-eval__git-stat`.\n' > "$TMP_ROOT/rules/tooling.md"
expect fail "an unregistered prefixed tool"

: > "$TMP_ROOT/rules/tooling.md"
printf -- '- `anvil-cron-list`\n' > "$SKILL"
expect fail "an Elisp function named as a bare tool"

printf -- '- `anvil-worker-call`\n' > "$SKILL"
expect fail "an unregistered bare tool"

# A file in BARE_FILES that does not exist must fail the check, not skip it.
# A second skill keeps the PREFIXED_FILES pattern matching, so only BARE_FILES is at fault.
mkdir -p "$TMP_ROOT/skills/other"
: > "$TMP_ROOT/skills/other/SKILL.md"
printf -- '- `cron-list`\n' > "$SKILL"
expect pass "a present bare-tool skill"
rm "$SKILL"
expect fail "a missing BARE_FILES path"
# The failure must name the missing file, so a crash for another reason does not pass.
err="$(ANVIL_NAMES_ROOT="$TMP_ROOT" "$REPO_ROOT/bin/check-anvil-names" 2>&1 >/dev/null || true)"
case "$err" in
  *"skills/anvil-advanced-ops/SKILL.md: no file matches"*) ;;
  *) echo "FAIL check-anvil-names: the missing BARE_FILES error does not name the file: $err" >&2; exit 1 ;;
esac
echo "ok check-anvil-names"
