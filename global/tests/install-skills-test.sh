#!/usr/bin/env bash
# install-skills must give each manual-only skill the Codex policy, and no other skill.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { echo "FAIL install-skills: $*" >&2; exit 1; }

HOME="$TMP_ROOT" "$REPO_ROOT/bin/install-skills.sh" >/dev/null

manual=0
for skill in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$skill")"
  for root in .claude/skills .agents/skills; do
    yaml="$TMP_ROOT/$root/$name/agents/openai.yaml"
    if grep -q '^disable-model-invocation: *true' "$skill/SKILL.md"; then
      grep -q '^  allow_implicit_invocation: false$' "$yaml" || fail "$name in $root has no Codex policy"
    elif [ ! -e "$skill/agents/openai.yaml" ] && [ -e "$yaml" ]; then
      fail "$name in $root is not manual-only but got a policy"
    fi
  done
  if grep -q '^disable-model-invocation: *true' "$skill/SKILL.md"; then manual=$((manual + 1)); fi
done
[ "$manual" -gt 0 ] || fail "no manual-only skill in skills/ to test"

# A second run must keep the result (rsync --delete wipes the generated file first).
HOME="$TMP_ROOT" "$REPO_ROOT/bin/install-skills.sh" >/dev/null
grep -q '^  allow_implicit_invocation: false$' "$TMP_ROOT/.agents/skills/architect/agents/openai.yaml" \
  || fail "second run lost the policy of architect"

# Git Bash on Windows has no rsync: the fallback copy must still install every
# skill, drop a stale file like rsync --delete, and keep the Codex policy.
NO_RSYNC="$TMP_ROOT/no-rsync-bin"
NO_HOME="$TMP_ROOT/no-rsync-home"
mkdir -p "$NO_RSYNC" "$NO_HOME/.claude/skills/architect"
for tool in dirname basename mkdir grep rm cp; do ln -s "$(command -v "$tool")" "$NO_RSYNC/$tool"; done
if (PATH="$NO_RSYNC"; command -v rsync >/dev/null 2>&1); then fail "the test PATH still has rsync"; fi
printf 'stale\n' > "$NO_HOME/.claude/skills/architect/stale.txt"
HOME="$NO_HOME" PATH="$NO_RSYNC" "$BASH" "$REPO_ROOT/bin/install-skills.sh" >/dev/null || fail "install without rsync failed"
for skill in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$skill")"
  for root in .claude/skills .agents/skills; do
    cmp -s "$skill/SKILL.md" "$NO_HOME/$root/$name/SKILL.md" || fail "$name in $root was not copied without rsync"
  done
done
[ ! -e "$NO_HOME/.claude/skills/architect/stale.txt" ] || fail "a stale file survived the copy without rsync"
grep -q '^  allow_implicit_invocation: false$' "$NO_HOME/.agents/skills/architect/agents/openai.yaml" \
  || fail "no Codex policy for architect without rsync"

echo "ok install-skills ($manual manual-only skills, with and without rsync)"
