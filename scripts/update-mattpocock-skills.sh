#!/usr/bin/env bash
set -euo pipefail

# Install/update Matt Pocock's skills (mattpocock/skills).
# The skills CLI installs canonical copies into ~/.agents/skills with
# --agent codex (Codex reads that dir directly); this script then rsyncs each
# skill into the shared skills/ dir as COPIES so Claude Code sees them too.
# The copies are deliberately NOT tracked by git — a marker-delimited block in
# .gitignore (regenerated on every run) keeps them out of the repo.
# code-review stays Codex-only: it would collide with Claude Code's built-in
# /code-review. Run after update-cli-skills.sh so ~/.agents/skills is fresh.
# Re-runnable; exits non-zero on failure.

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
MATT_CLAUDE_DENY="code-review"

# The skills CLI prints "Failed to ..." lines but still exits 0 on partial
# failures (unreachable source, per-skill error). Treat those as failures too.
run_skills() { # args... -> streams output, returns 1 on any failure
  local out rc=0
  out="$(npx --yes skills@latest "$@" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'Failed to '; }
}

fail=0

section "Matt Pocock skills (mattpocock/skills, canonical: ~/.agents/skills)"
if [ -f "$LOCK" ] && grep -q 'mattpocock/skills' "$LOCK"; then
  info "already installed (refreshed by update-cli-skills.sh)"
else
  info "installing"
  if run_skills add mattpocock/skills --skill '*' --agent codex --global --yes; then
    info "mattpocock/skills installed"
  else
    warn "mattpocock/skills install failed"
    fail=1
  fi
fi

section "Syncing copies for Claude Code"
if ! command -v jq >/dev/null 2>&1; then
  warn "jq is required to parse ${LOCK}"
  exit 1
fi
matt_list="$(jq -r '[.skills // {} | to_entries[]
    | select(.value | tostring | contains("mattpocock/skills")) | .key]
  | sort | .[]' "$LOCK" 2>/dev/null)" || matt_list=""
# Windows jq emits CRLF; a trailing \r in a name breaks the SKILL.md source
# check and puts bad entries in the .gitignore block.
matt_list="${matt_list//$'\r'/}"
if [ -z "$matt_list" ]; then
  # Do not touch the .gitignore block: existing copies must stay ignored.
  warn "no mattpocock/skills entries found in ${LOCK}; skipping sync"
  fail=1
  exit $fail
fi

copied=0
sync_names=()
ignore_entries=()
for name in $matt_list; do
  [ "$name" = "$MATT_CLAUDE_DENY" ] && continue
  sync_names+=("$name")
  if [ ! -f "${AGENTS_SKILLS_DIR}/${name}/SKILL.md" ]; then
    warn "missing source skill: ${AGENTS_SKILLS_DIR}/${name}"
    fail=1
  elif ! install_skill_copy "${AGENTS_SKILLS_DIR}/${name}" "${SKILLS_DIR}/${name}"; then
    fail=1
  else
    copied=$((copied + 1))
  fi
  # Keep ignoring an existing copy even when this run's sync failed, so a
  # transient failure can't surface third-party files as trackable.
  if [ -d "${SKILLS_DIR}/${name}" ]; then
    ignore_entries+=("skills/${name}")
  fi
done
info "copied ${copied} skills into ${SKILLS_DIR} (deny: ${MATT_CLAUDE_DENY})"

protected_names=()
while IFS= read -r name; do
  protected_names+=("$name")
done < <(gitignore_block_skill_names "$GITIGNORE" "cli-skills")
if ! cleanup_marked_skill_copies "$SKILLS_DIR" "$AGENTS_SKILLS_DIR" \
  "${sync_names[@]}" "${protected_names[@]}"; then
  fail=1
fi

regen_gitignore_block "$GITIGNORE" "matt-skills" "update-mattpocock-skills.sh" \
  ${ignore_entries[@]+"${ignore_entries[@]}"}
info "regenerated matt-skills block in .gitignore"

[ "$fail" -eq 0 ] || exit 1
section "mattpocock-skills done"
