#!/usr/bin/env bash
set -euo pipefail

# Sync the repo's tracked skills into ~/.agents/skills as COPIES.
# Root policy: each CLI reads exactly one skills root — Claude Code reads
# skills/ (via ~/.claude/skills), Codex reads only ~/.agents/skills. The
# old ~/.codex/skills symlink is gone: it made Codex load the shared repo
# root too and see every skill present in both roots twice. Third-party
# copies in skills/ are untracked and already canonical in ~/.agents/skills,
# so only tracked skills flow this way. Re-runnable; exits non-zero on failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"

fail=0

section "Repo skills → ~/.agents/skills (Codex surface)"

# Root-policy drift guard: the old ~/.codex/skills symlink (or user skills
# placed there) means Codex double-loads. The Codex CLI recreates
# ~/.codex/skills/.system for its bundled system skills — that alone is fine.
codex_skills="${HOME}/.codex/skills"
if [ -L "$codex_skills" ]; then
  warn "~/.codex/skills is a symlink; Codex double-loads skills — remove it (Codex reads only ~/.agents/skills)"
  fail=1
elif [ -d "$codex_skills" ] \
  && find "$codex_skills" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) ! -name '.system' 2>/dev/null | grep -q .; then
  warn "~/.codex/skills has entries besides .system; Codex double-loads them — move them to ~/.agents/skills"
  fail=1
fi

tracked="$(git -C "$REPO_ROOT" ls-files 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u)"
if [ -z "$tracked" ]; then
  warn "no tracked skills found under ${SKILLS_DIR}"
  exit 1
fi

mkdir -p "$AGENTS_SKILLS_DIR"
copied=0
for name in $tracked; do
  if install_skill_copy "${SKILLS_DIR}/${name}" "${AGENTS_SKILLS_DIR}/${name}"; then
    copied=$((copied + 1))
  else
    fail=1
  fi
done
info "copied ${copied} tracked skills into ${AGENTS_SKILLS_DIR}"

# Marker-scoped orphan cleanup: a delete/rename in skills/ must also remove
# the old copy on the Codex surface, or ghost skills accumulate there.
# Markers prove the copy is ours; unmarked dirs (skills CLI installs,
# hand-managed skills) are never touched.
for marker in "$AGENTS_SKILLS_DIR"/*/.agent-scripts-copy; do
  [ -f "$marker" ] || continue
  case "$(cat "$marker")" in "${SKILLS_DIR}"/*) ;; *) continue ;; esac
  name="$(basename "$(dirname "$marker")")"
  if ! printf '%s\n' "$tracked" | grep -qxF "$name"; then
    if rm -rf "${AGENTS_SKILLS_DIR:?}/${name}"; then
      info "removed orphaned copy: ${name}"
    else
      fail=1
    fi
  fi
done

[ "$fail" -eq 0 ] || exit 1
section "repo-skills done"
