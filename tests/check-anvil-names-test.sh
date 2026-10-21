#!/usr/bin/env bash
# check-anvil-names must reject the stale names this repo once shipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SKILL="$TMP_ROOT/other-skills/marcus/anvil-advanced-ops/SKILL.md"
mkdir -p "$TMP_ROOT/agent-tooling" "$TMP_ROOT/rules" "$(dirname "$SKILL")"
printf '%s\n' mcp__anvil__emacs-eval mcp__anvil__emacs-eval-async \
  mcp__anvil-emacs-eval__cron-list mcp__anvil-emacs-eval__git-status \
  > "$TMP_ROOT/agent-tooling/anvil-tools.txt"
: > "$TMP_ROOT/AGENTS.MD"

run() { ANVIL_NAMES_ROOT="$TMP_ROOT" "$REPO_ROOT/agent-tooling/check-anvil-names" >/dev/null 2>&1; }
expect() { # expect <pass|fail> <label>
  if run; then got=pass; else got=fail; fi
  [ "$got" = "$1" ] || { echo "FAIL check-anvil-names: expected $1 for $2" >&2; exit 1; }
}

printf 'Use `mcp__anvil-emacs-eval__git-status` and `mcp__anvil__emacs-eval*`.\n' > "$TMP_ROOT/rules/tooling.md"
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
