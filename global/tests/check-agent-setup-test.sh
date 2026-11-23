#!/usr/bin/env bash
# Check the public script with isolated repos and real instruction pointers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
fail() { printf 'FAIL check-agent-setup: %s\n' "$*" >&2; exit 1; }

# A copy from Git Bash's default ln mode must not count as a fixture link.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) export MSYS=winsymlinks:nativestrict ;; esac
printf 'probe\n' > "$TMP_ROOT/target"
if ! ln -s target "$TMP_ROOT/probe" 2>/dev/null || [ ! -L "$TMP_ROOT/probe" ]; then
  fail 'cannot create fixture links; on Windows, rerun in an elevated Git Bash or turn on Developer Mode'
fi

export HOME="$TMP_ROOT/home with spaces"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
git config --global core.symlinks true
for name in agent-scripts claude-code-settings codex-settings pi-settings; do
  git init -q "$HOME/Projects/$name"
  git -C "$HOME/Projects/$name" config core.symlinks true
done
SOURCE="$HOME/Projects/agent-scripts/global"
mkdir -p "$SOURCE/rules" "$SOURCE/skills/example" "$SOURCE/skills/manual" "$HOME/.claude" "$HOME/.codex" "$HOME/.pi/agent"
printf 'global rules\n' > "$SOURCE/AGENTS.md"
printf 'generated rules\n' > "$SOURCE/AGENTS.codex.md"
printf 'tool rules\n' > "$SOURCE/rules/tooling.md"
printf 'example skill\n' > "$SOURCE/skills/example/SKILL.md"
printf '%s\n' '---' 'disable-model-invocation: true' '---' > "$SOURCE/skills/manual/SKILL.md"
# Use the actual installer, including its generated policy for the manual skill.
mkdir -p "$SOURCE/bin" "$SOURCE/../agent-tooling"
cp "$ROOT/bin/install-skills.sh" "$SOURCE/bin/"
cp "$ROOT/../agent-tooling/lib-copies.sh" "$SOURCE/../agent-tooling/"
bash "$SOURCE/bin/install-skills.sh" >/dev/null
ln -s "$SOURCE/AGENTS.md" "$HOME/.claude/CLAUDE.md"
ln -s "$SOURCE/rules" "$HOME/.claude/agent-rules"
ln -s "$SOURCE/AGENTS.codex.md" "$HOME/.codex/AGENTS.md"
ln -s "$SOURCE/AGENTS.codex.md" "$HOME/.pi/agent/AGENTS.md"

check() {
  local expected="$1" lines="$2" code=0
  shift 2
  output="$(bash "$ROOT/bin/check-agent-setup.sh" "$@")" || code=$?
  [ "$code" -eq "$expected" ] || fail "expected exit $expected, got $code: $output"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq "$lines" ] || fail "expected $lines lines: $output"
  [[ "$output" != *"$HOME"* ]] || fail 'output exposes HOME'
  if [ "$expected" -eq 0 ]; then
    [[ "$output" != *✗* ]] || fail "unexpected failure: $output"
  else
    [[ "$output" == *✗* ]] || fail "missing failure mark: $output"
  fi
}

check 0 4
rm "$HOME/.claude/CLAUDE.md"
printf '%s\n' "$SOURCE/AGENTS.md" > "$HOME/.claude/CLAUDE.md"
check 1 4
[[ "$output" == *'✗ 3.'* ]] || fail 'text pointer did not fail check 3'
check 0 2 --preflight
rm "$HOME/.claude/CLAUDE.md"
ln -s "$SOURCE/AGENTS.codex.md" "$HOME/.claude/CLAUDE.md"
check 1 4
[[ "$output" == *'✗ 3.'* ]] || fail 'wrong target did not fail check 3'
rm "$HOME/.claude/CLAUDE.md"
ln -s "$SOURCE/AGENTS.md" "$HOME/.claude/CLAUDE.md"

printf 'stale\n' > "$HOME/.agents/skills/example/SKILL.md"
check 1 4
[[ "$output" == *'✗ 4.'* ]] || fail 'stale skill did not fail check 4'
cp "$SOURCE/skills/example/SKILL.md" "$HOME/.agents/skills/example/SKILL.md"
git -C "$HOME/Projects/pi-settings" config core.symlinks false
check 1 4
[[ "$output" == *'✗ 1.'* ]] || fail 'local false did not fail check 1'
git -C "$HOME/Projects/pi-settings" config core.symlinks true
mv "$HOME/Projects/pi-settings" "$HOME/pi-settings-saved"
check 1 2 --preflight
[[ "$output" == *'missing repo'* ]] || fail 'missing repo did not fail check 1'
mv "$HOME/pi-settings-saved" "$HOME/Projects/pi-settings"
check 0 4

printf 'ok check-agent-setup (pointers, skills, Git settings, missing repo, preflight)\n'
