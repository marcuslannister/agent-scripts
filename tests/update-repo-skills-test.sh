#!/usr/bin/env bash
set -euo pipefail

# Black-box tests for scripts/update-repo-skills.sh (issue #2): the script
# runs as a subprocess from a scratch git repo with HOME pointed at a scratch
# dir, and every assertion is on filesystem state or exit codes only.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FAKE_HOME="$TMPDIR/home"
REPO="$TMPDIR/repo"
SURFACE="$FAKE_HOME/.agents/skills"

mkdir -p "$REPO/scripts" "$REPO/skills" "$FAKE_HOME"
cp "$REPO_ROOT/scripts/update-repo-skills.sh" "$REPO_ROOT/scripts/lib-copies.sh" "$REPO/scripts/"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test

make_skill() { # name
  mkdir -p "$REPO/skills/$1"
  printf '%s\n' '---' "name: $1" '---' > "$REPO/skills/$1/SKILL.md"
}

run_sync() { HOME="$FAKE_HOME" "$REPO/scripts/update-repo-skills.sh"; }

# Tracked skills appear on the Codex surface as marked copies; untracked
# skill dirs are excluded by construction (enumeration is git-tracked only).
make_skill alpha
make_skill beta
git -C "$REPO" add .
git -C "$REPO" commit -qm init
make_skill gamma # left untracked on purpose
run_sync >/dev/null
test -f "$SURFACE/alpha/SKILL.md"
test "$(cat "$SURFACE/alpha/.agent-scripts-copy")" = "$REPO/skills/alpha"
test -f "$SURFACE/beta/SKILL.md"
test ! -e "$SURFACE/gamma"

# Second run over an already-synced surface is a green no-op.
run_sync >/dev/null
test -f "$SURFACE/alpha/.agent-scripts-copy"

# Orphan cleanup: a tracked skill deleted (alpha) or renamed (beta -> delta)
# also leaves the Codex surface; the new name appears in the same run.
git -C "$REPO" rm -q -r skills/alpha
git -C "$REPO" mv skills/beta skills/delta
git -C "$REPO" commit -qm "delete alpha, rename beta"
run_sync >/dev/null
test ! -e "$SURFACE/alpha"
test ! -e "$SURFACE/beta"
test -f "$SURFACE/delta/SKILL.md"
test "$(cat "$SURFACE/delta/.agent-scripts-copy")" = "$REPO/skills/delta"

# Unmarked dirs on the surface (skills CLI installs, hand-managed skills)
# survive every run untouched — including runs where cleanup fires.
mkdir -p "$SURFACE/hand-made"
printf 'mine\n' > "$SURFACE/hand-made/SKILL.md"
make_skill epsilon
git -C "$REPO" add skills/epsilon # not `add .` — gamma must stay untracked
git -C "$REPO" rm -q -r skills/delta
git -C "$REPO" commit -qm "add epsilon, delete delta"
run_sync >/dev/null
test ! -e "$SURFACE/delta"
test -f "$SURFACE/epsilon/SKILL.md"
test "$(cat "$SURFACE/hand-made/SKILL.md")" = "mine"

# Drift guard: the old ~/.codex/skills symlink means Codex double-loads; the
# run must exit non-zero while leaving the sync's own work intact.
mkdir -p "$FAKE_HOME/.codex"
ln -s "$REPO/skills" "$FAKE_HOME/.codex/skills"
if run_sync >/dev/null 2>&1; then
  echo "FAIL: drift guard did not fail the run" >&2
  exit 1
fi
test -f "$SURFACE/epsilon/SKILL.md" # sync still ran; only the exit is red
test "$(cat "$SURFACE/hand-made/SKILL.md")" = "mine"
rm -rf "$FAKE_HOME/.codex"
run_sync >/dev/null # guard clears once the symlink is gone

# Codex's own bundled skills under ~/.codex/skills/.system are not drift;
# a user skill dir sitting beside .system is.
mkdir -p "$FAKE_HOME/.codex/skills/.system/bundled-skill"
run_sync >/dev/null # .system alone stays green
mkdir -p "$FAKE_HOME/.codex/skills/stray-skill"
if run_sync >/dev/null 2>&1; then
  echo "FAIL: user entry beside .system did not fail the run" >&2
  exit 1
fi
rm -rf "$FAKE_HOME/.codex"
run_sync >/dev/null

# Empty tracked set: the script refuses to run rather than treating every
# copy as an orphan — a broken enumeration must never mass-delete the surface.
git -C "$REPO" rm -q -r skills/epsilon
git -C "$REPO" commit -qm "delete last tracked skill"
if run_sync >/dev/null 2>&1; then
  echo "FAIL: ran against an empty tracked set" >&2
  exit 1
fi
test -f "$SURFACE/epsilon/SKILL.md" # ghost survives; safety beats cleanup here
test "$(cat "$SURFACE/hand-made/SKILL.md")" = "mine"

# Fail-loud: a copy the installer refuses (unmarked dir with a diverging
# SKILL.md) fails the whole run, while unrelated skills still sync and the
# now-restored tracked set lets the epsilon ghost get cleaned.
make_skill zeta
make_skill eta
git -C "$REPO" add skills/zeta skills/eta
git -C "$REPO" commit -qm "add zeta and eta"
mkdir -p "$SURFACE/zeta"
printf 'diverged\n' > "$SURFACE/zeta/SKILL.md"
if run_sync >/dev/null 2>&1; then
  echo "FAIL: refused copy did not fail the run" >&2
  exit 1
fi
test "$(cat "$SURFACE/zeta/SKILL.md")" = "diverged" # refused dir untouched
test -f "$SURFACE/eta/.agent-scripts-copy"          # unrelated skill synced
test ! -e "$SURFACE/epsilon"                        # ghost cleaned

# No-rsync fallback: with rsync absent from PATH, the cp fallback still
# produces a marked copy (Git Bash on Windows ships no rsync).
BINDIR="$TMPDIR/bin"
mkdir -p "$BINDIR"
for tool in bash git mkdir rm cp mv cat cut sort grep find cmp touch dirname basename sed; do
  ln -s "$(command -v "$tool")" "$BINDIR/$tool"
done
rm -rf "$SURFACE/zeta" # clear the collision; the next sync recreates it
HOME="$FAKE_HOME" PATH="$BINDIR" "$REPO/scripts/update-repo-skills.sh" >/dev/null
test -f "$SURFACE/zeta/SKILL.md"
test "$(cat "$SURFACE/zeta/.agent-scripts-copy")" = "$REPO/skills/zeta"

echo "update-repo-skills tests passed"
