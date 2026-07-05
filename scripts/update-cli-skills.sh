#!/usr/bin/env bash
set -euo pipefail

# Refresh all skills.sh-managed agent skills (npx-only skill repos).
# Removes legacy tw93/Waza skills-CLI installs (Waza is a marketplace plugin
# now, via update-waza.sh), bootstraps find-skills (vercel-labs/skills) when
# missing, then runs the CLI's global update — which refreshes every
# skills.sh-managed package, including mattpocock/skills' canonical copies
# (its bootstrap and Claude-side copy sync live in update-mattpocock-skills.sh,
# which must run after this). One-off npx skills both agents need (find-skills)
# are rsynced into the shared skills/ dir as untracked COPIES here.
# Exits non-zero if any step fails.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

LOCK="${HOME}/.agents/.skill-lock.json"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"
GITIGNORE="${REPO_ROOT}/.gitignore"
SKILLS_CLI_AGENT=codex
SHARED_SKILLS=(find-skills)
SHARED_SKILLS_REPO="vercel-labs/skills"

# The skills CLI prints "Failed to ..." lines but still exits 0 on partial
# failures (unreachable source, per-skill error). Treat those as failures too.
run_skills() { # args... -> streams output, returns 1 on any failure
  local out rc=0
  out="$(npx --yes skills@latest "$@" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'Failed to '; }
}

fail=0

section "Removing legacy Waza skills-CLI installs"
waza_list=""
if [ -f "$LOCK" ]; then
  waza_list="$(jq -r '.skills | to_entries[] | select(.value.source == "tw93/Waza") | .key' "$LOCK" 2>/dev/null)" || waza_list=""
fi
if [ -n "$waza_list" ]; then
  # shellcheck disable=SC2086 — skill names are single words from the lock
  if run_skills remove $waza_list --global --agent "$SKILLS_CLI_AGENT" --yes; then
    info "removed legacy Waza skills: $(printf '%s ' $waza_list)"
  else
    warn "failed to remove legacy Waza skills"
    fail=1
  fi
  # The skills CLI can leave orphan dirs behind after remove (seen on macOS).
  for name in $waza_list; do
    rm -rf "${AGENTS_SKILLS_DIR:?}/${name}"
  done
else
  info "no legacy Waza installs"
fi

section "find-skills (${SHARED_SKILLS_REPO}, canonical: ~/.agents/skills)"
if [ -f "$LOCK" ] && grep -q "$SHARED_SKILLS_REPO" "$LOCK"; then
  info "already installed"
else
  info "installing"
  if run_skills add "$SHARED_SKILLS_REPO" --skill find-skills --agent codex --global --yes; then
    info "find-skills installed"
  else
    warn "find-skills install failed"
    fail=1
  fi
fi

section "Updating global skills"
if run_skills update --global --yes; then
  info "skills updated"
else
  warn "skills update failed"
  fail=1
fi

section "Syncing shared copies for Claude Code"
ignore_entries=()
for name in "${SHARED_SKILLS[@]}"; do
  if [ ! -f "${AGENTS_SKILLS_DIR}/${name}/SKILL.md" ]; then
    warn "missing source skill: ${AGENTS_SKILLS_DIR}/${name}"
    fail=1
  elif ! install_skill_copy "${AGENTS_SKILLS_DIR}/${name}" "${SKILLS_DIR}/${name}"; then
    fail=1
  else
    info "skill copied -> ${SKILLS_DIR}/${name}"
  fi
  # Keep ignoring an existing copy even when this run's sync failed, so a
  # transient failure can't surface third-party files as trackable.
  if [ -d "${SKILLS_DIR}/${name}" ]; then
    ignore_entries+=("skills/${name}")
  fi
done
regen_gitignore_block "$GITIGNORE" "cli-skills" "update-cli-skills.sh" \
  ${ignore_entries[@]+"${ignore_entries[@]}"}
info "regenerated cli-skills block in .gitignore"

section "cli-skills done"
exit $fail
