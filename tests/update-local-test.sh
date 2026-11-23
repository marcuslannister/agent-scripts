#!/usr/bin/env bash
set -euo pipefail

# Secondary-machine updater (ADR-0009): pull first, then CLIs, plugins, and
# distribute. It never acquires staging, and it re-execs exactly once so a run
# always uses the freshly pulled script.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
SCRIPTS="$FIXTURE/agent-tooling"
GIT_BIN="$TMP_ROOT/git-bin"
mkdir -p "$SCRIPTS" "$GIT_BIN" "$FIXTURE/global/bin"
cp "$REPO_ROOT/agent-tooling/update-local.sh" "$SCRIPTS/"

STEPS=(update-agents.sh update-plugins.sh sync-skill-surfaces.sh)
write_steps() { # exit_code_for_first_step
  local code="${1:-0}" step
  for step in "${STEPS[@]}"; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
      > "$SCRIPTS/$step"
    chmod +x "$SCRIPTS/$step"
  done
  if [ "$code" -ne 0 ]; then
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
      "exit $code" \
      > "$SCRIPTS/update-agents.sh"
    chmod +x "$SCRIPTS/update-agents.sh"
  fi
}

# The own skills step: global/bin/install-skills.sh, logged like the others.
write_skills_step() { # exit_code [stderr_text]
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
    "${2:+printf '%s\\n' '$2' >&2}" \
    "exit ${1:-0}" \
    > "$FIXTURE/global/bin/install-skills.sh"
  chmod +x "$FIXTURE/global/bin/install-skills.sh"
}

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "$*" >> "$GIT_LOG"' \
  '[ "${FAKE_GIT_FAIL:-0}" -eq 0 ]' \
  > "$GIT_BIN/git"
chmod +x "$GIT_BIN/git"

UPDATE_LOG="$TMP_ROOT/update.log"
GIT_LOG="$TMP_ROOT/git.log"
export UPDATE_LOG GIT_LOG

run_local() {
  PATH="$GIT_BIN:$PATH" "$SCRIPTS/update-local.sh" "$@"
}

# Happy path: pull first, then every step once, in order, own skills last.
write_steps 0
write_skills_step 0
: > "$UPDATE_LOG"
: > "$GIT_LOG"
run_local > "$TMP_ROOT/out" 2>&1

printf '%s\n' "${STEPS[@]}" install-skills.sh > "$TMP_ROOT/expected.log"
cmp "$TMP_ROOT/expected.log" "$UPDATE_LOG"
rg -F -- '-C '"$FIXTURE"' pull --ff-only' "$GIT_LOG" >/dev/null
test "$(wc -l < "$GIT_LOG" | tr -d ' ')" -eq 1
grep -F 'repository pull' "$TMP_ROOT/out" >/dev/null
grep -F 'native plugins' "$TMP_ROOT/out" >/dev/null
grep -F 'skill distribute' "$TMP_ROOT/out" >/dev/null
grep -F 'own skills' "$TMP_ROOT/out" >/dev/null
# Secondary machines never acquire staging.
grep -F 'skill acquire' "$TMP_ROOT/out" && { echo "FAIL: update-local acquired" >&2; exit 1; }

# A failed pull warns and continues with local content, but the run fails.
: > "$UPDATE_LOG"
: > "$GIT_LOG"
set +e
FAKE_GIT_FAIL=1 run_local > "$TMP_ROOT/pull-fail.out" 2>&1
pull_fail_code=$?
set -e
test "$pull_fail_code" -eq 1
cmp "$TMP_ROOT/expected.log" "$UPDATE_LOG"
rg -F 'could not fast-forward' "$TMP_ROOT/pull-fail.out" >/dev/null

# A failed plugin refresh is reported but never fails the run (ADR-0009).
write_steps 0
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf '\''%s\n'\'' "${0##*/}" >> "$UPDATE_LOG"' \
  'exit 9' \
  > "$SCRIPTS/update-plugins.sh"
chmod +x "$SCRIPTS/update-plugins.sh"
: > "$UPDATE_LOG"
run_local > "$TMP_ROOT/plugin-fail.out" 2>&1
cmp "$TMP_ROOT/expected.log" "$UPDATE_LOG"
rg '✗.*native plugins' "$TMP_ROOT/plugin-fail.out" >/dev/null

# A failed own skills install is one warning that carries the cause. The run
# continues and still exits 0, like the plugin refresh.
write_steps 0
write_skills_step 7 'boom: no space left'
: > "$UPDATE_LOG"
run_local > "$TMP_ROOT/skills-fail.out" 2>&1
cmp "$TMP_ROOT/expected.log" "$UPDATE_LOG"
test "$(rg -c 'own skills install failed' "$TMP_ROOT/skills-fail.out")" -eq 1
rg -F 'own skills install failed: boom: no space left' "$TMP_ROOT/skills-fail.out" >/dev/null
rg '✗.*own skills' "$TMP_ROOT/skills-fail.out" >/dev/null
write_skills_step 0

# A failed step does not stop the others, and the run exits non-zero.
write_steps 17
: > "$UPDATE_LOG"
: > "$GIT_LOG"
set +e
run_local > "$TMP_ROOT/step-fail.out" 2>&1
step_fail_code=$?
set -e
test "$step_fail_code" -eq 1
cmp "$TMP_ROOT/expected.log" "$UPDATE_LOG"

echo "update-local tests passed"
