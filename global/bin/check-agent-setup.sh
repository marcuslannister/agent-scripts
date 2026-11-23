#!/usr/bin/env bash
# Check setup without changing the repos, pointers, or installed skills.
set -euo pipefail

case "$*" in
  ''|--preflight) ;;
  *) printf 'Usage: bash global/bin/check-agent-setup.sh [--preflight]\n' >&2; exit 1 ;;
esac

failed=0
windows=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows=true ;; esac
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
SOURCE="$HOME/Projects/agent-scripts/global"

report() {
  local message="$2"
  message="${message//"$HOME"/\~}"
  if [ "$1" = pass ]; then
    printf '✓ %s\n' "$message"
  else
    printf '✗ %s\n' "$message"
    failed=1
  fi
}

# 1. Read the effective setting in each repo, including local overrides.
issues=
if "$windows" && [ "$(git config --global --bool core.symlinks 2>/dev/null || true)" != true ]; then
  issues+=' global core.symlinks is not true; run git config --global core.symlinks true;'
fi
for name in agent-scripts claude-code-settings codex-settings pi-settings; do
  repo="$HOME/Projects/$name"
  if [ ! -e "$repo/.git" ] || ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    issues+=" missing repo $repo; clone it;"
  elif [ "$(git -C "$repo" config --bool core.symlinks 2>/dev/null || true)" = false ]; then
    issues+=" $repo has core.symlinks=false; run git -C \"\$HOME/Projects/$name\" config core.symlinks true;"
  fi
done
if [ -z "$issues" ]; then
  report pass '1. Git makes links: all four repos allow links'
else
  report fail "1. Git makes links:$issues"
fi

# 2. Native strict mode prevents Git Bash from silently copying the target.
details=
if "$windows"; then
  system32="$(cygpath -u "${SYSTEMROOT:-${WINDIR:-}}")/System32"
  developer=unknown
  if registry="$("$system32/reg.exe" query 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' //v AllowDevelopmentWithoutDevLicense 2>/dev/null)"; then
    developer=off
    if [[ "$registry" =~ REG_DWORD[[:space:]]+0x0*1([[:space:]]|$) ]]; then developer=on; fi
  elif [ -x "$system32/reg.exe" ]; then
    developer=off
  fi
  elevated=no
  if "$system32/net.exe" session >/dev/null 2>&1; then elevated=yes; fi
  details=" (Developer Mode: $developer; elevated: $elevated)"
  if [ "$developer" = off ]; then details+='; warning: only elevated sessions can make links'; fi
fi
printf 'link test\n' > "$TMP_ROOT/target"
if { if "$windows"; then
       MSYS=winsymlinks:nativestrict ln -s target "$TMP_ROOT/link"
     else
       ln -s target "$TMP_ROOT/link"
     fi; } 2>/dev/null && [ -L "$TMP_ROOT/link" ]; then
  report pass "2. This session can make a link$details"
else
  fix='check link permissions and the temporary filesystem'
  if "$windows"; then fix='turn on Developer Mode or use an elevated shell (Run as administrator)'; fi
  report fail "2. This session cannot make a link$details; $fix"
fi

if [ "${1:-}" = --preflight ]; then exit "$failed"; fi

# 3. Compare the content, not just the recorded link target.
issues=
for pointer in .claude/CLAUDE.md .claude/agent-rules .codex/AGENTS.md .pi/agent/AGENTS.md; do
  case "$pointer" in
    .claude/CLAUDE.md) source_path="$SOURCE/AGENTS.md" ;;
    .claude/agent-rules) source_path="$SOURCE/rules" ;;
    *) source_path="$SOURCE/AGENTS.codex.md" ;;
  esac
  if [ ! -L "$HOME/$pointer" ] \
    || { [ "$pointer" = .claude/agent-rules ] && [ ! -d "$HOME/$pointer" ]; } \
    || { [ "$pointer" != .claude/agent-rules ] && [ ! -f "$HOME/$pointer" ]; } \
    || ! diff -r "$source_path" "$HOME/$pointer" >/dev/null 2>&1; then
    issues+=" ~/$pointer;"
  fi
done
if [ -z "$issues" ]; then
  report pass '3. The four pointers are links and match global/'
else
  report fail "3. The four pointers are missing or differ:$issues check ~/Projects/agent-scripts/global/ and the tracked settings links (docs/windows.md)"
fi

# 4. The installer adds a policy file for manual-only skills without one.
issues=
shopt -s nullglob
found_skill=false
for skill in "$SOURCE"/skills/*/; do
  found_skill=true
  name="$(basename "$skill")"
  expected="$TMP_ROOT/skills/$name"
  mkdir -p "$expected"
  if ! cp -R "$skill/." "$expected/" 2>/dev/null; then
    issues+=" cannot read source skill $name;"
    continue
  fi
  if grep -q '^disable-model-invocation: *true' "$skill/SKILL.md" && [ ! -e "$expected/agents/openai.yaml" ]; then
    mkdir -p "$expected/agents"
    printf 'policy:\n  allow_implicit_invocation: false\n' > "$expected/agents/openai.yaml"
  fi
  for root in .claude/skills .agents/skills; do
    copy="$HOME/$root/$name"
    if [ -L "$copy" ] || [ ! -d "$copy" ] || ! diff -r "$expected" "$copy" >/dev/null 2>&1; then
      issues+=" ~/$root/$name;"
    fi
  done
done
if ! "$found_skill"; then
  issues+=' no source skills in ~/Projects/agent-scripts/global/skills/;'
fi
if [ -z "$issues" ]; then
  report pass '4. The own skills match in both surfaces'
else
  report fail "4. The own skills are missing or stale:$issues run bash ~/Projects/agent-scripts/global/bin/install-skills.sh"
fi
exit "$failed"
