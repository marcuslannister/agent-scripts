#!/usr/bin/env bash
# check-privacy and the hooks dispatcher: block new home paths, emails, and
# secrets; ignore old lines, allowlisted paths, and lines a merge only carries.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Keep the runner's own Git config (and any global hooks path) out of the test.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
OWN="me@own""dev.io"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL="$OWN" GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL="$OWN"
export GITLEAKS="$TMP_ROOT/no-gitleaks"

# Fixture strings are built at run time, so this file holds no real hit.
U=Users H=home
LEAK_PATH="/$U/alice/notes"
LEAK_MAIL="alice@acme""corp.io"

CHECK="$REPO_ROOT/agent-tooling/check-privacy"
REPO="$TMP_ROOT/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "$OWN"
cd "$REPO"

fail() { echo "FAIL check-privacy: $*" >&2; exit 1; }
staged() { # staged <pass|fail> <label>
  if "$CHECK" --staged >"$TMP_ROOT/out" 2>&1; then got=pass; else got=fail; fi
  [ "$got" = "$1" ] || { cat "$TMP_ROOT/out" >&2; fail "expected $1 for $2"; }
}
add() { printf '%s\n' "$2" >> "$1"; git add "$1"; }
commit() { git commit -q -m "$1"; }

add clean.txt "plain text"
staged pass "a clean file"
commit init

add a.txt "path $LEAK_PATH"
staged fail "a home path"
grep -q 'a.txt:1: home path' "$TMP_ROOT/out" || fail "report names file, line, and kind"
git reset -q a.txt; rm a.txt

add b.txt "x=/$H/bob/.cache"
staged fail "a home path after ="
git reset -q b.txt; rm b.txt

add ok.nix "./$H/$H.nix sunaku/$H/blob /$U/\$USER /$U/<name> /$U/Shared/x /$H/linuxbrew ~/$H/x"
staged pass "relative paths, templates, and shared dirs"
commit ok

add mail.txt "ask $LEAK_MAIL"
staged fail "a foreign email"
git reset -q mail.txt; rm mail.txt

add okmail.txt "noreply@anthropic.com 1+x@users.noreply.github.com a@example.com git@github.com:o/r.git $(printf %s "$OWN" | tr a-z A-Z)"
staged pass "noreply, example, git remote, and own addresses"
commit okmail

git commit -q --allow-empty -m base
printf 'old %s\n' "$LEAK_PATH" > legacy.txt; git add legacy.txt; commit legacy
add legacy.txt "new clean line"
staged pass "an old hit on an unchanged line"
commit legacy2

mkdir -p vendor/deep
add vendor/deep/x.md "$LEAK_PATH"
staged fail "a hit before the allowlist"
add .privacy-allow "vendor/**"
staged pass "an allowlisted path"
commit vendor

# Merge: lines that a parent already has pass; a line new to both fails.
git checkout -q -b side
add side.txt "upstream $LEAK_MAIL"
commit side
git checkout -q main
add main.txt "main work"
commit main-work
git merge -q --no-commit --no-ff side
staged pass "lines a merge only carries"
printf 'resolution %s\n' "$LEAK_PATH" >> main.txt; git add main.txt
staged fail "a new line in a merge"
git merge --abort

# Commit message: comments and the scissors diff are ignored.
msg="$TMP_ROOT/msg"
printf 'fix: x\n\n# %s\n# ------------------------ >8 ------------------------\n+%s\n' "$LEAK_PATH" "$LEAK_PATH" > "$msg"
"$CHECK" --message "$msg" >/dev/null 2>&1 || fail "comments and scissors in a message"
printf 'fix: x\n\nseen in %s\n' "$LEAK_PATH" > "$msg"
if "$CHECK" --message "$msg" >/dev/null 2>&1; then fail "a home path in a message"; fi

# Secret scan: a found tool decides; a missing tool warns.
printf '#!/bin/sh\ncat >/dev/null; echo leak; exit 1\n' > "$TMP_ROOT/leaky"; chmod +x "$TMP_ROOT/leaky"
add s.txt "token"
GITLEAKS="$TMP_ROOT/leaky" staged fail "a gitleaks finding"
staged pass "no gitleaks"
grep -q 'gitleaks not found' "$TMP_ROOT/out" || fail "warn when gitleaks is missing"
git reset -q s.txt; rm s.txt

# --files scans whole files.
printf 'see %s\n' "$LEAK_PATH" > full.txt
if "$CHECK" --files full.txt >/dev/null 2>&1; then fail "--files with a hit"; fi
"$CHECK" --files clean.txt >/dev/null 2>&1 || fail "--files on a clean file"
rm full.txt

# Dispatcher: the guard runs, then the repo's own hook still runs.
git config core.hooksPath "$REPO_ROOT/hooks"
printf '#!/bin/sh\ntouch "%s/local-ran"\n' "$TMP_ROOT" > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
add d.txt "fine"
git commit -q -m "feat: d" || fail "a clean commit through the dispatcher"
[ -e "$TMP_ROOT/local-ran" ] || fail "the local pre-commit hook did not run"
add e.txt "$LEAK_PATH"
if git commit -q -m "feat: e" >/dev/null 2>&1; then fail "the dispatcher let a hit through"; fi
git reset -q e.txt; rm e.txt
add f.txt "fine"
if git commit -q -m "feat: f from $LEAK_PATH" >/dev/null 2>&1; then fail "the dispatcher let a message hit through"; fi

echo "check-privacy tests passed"
