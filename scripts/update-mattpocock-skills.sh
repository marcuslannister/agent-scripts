#!/usr/bin/env bash
set -euo pipefail

# Install/update Matt Pocock's skills (mattpocock/skills).
# The skills CLI installs canonical copies into ~/.agents/skills with
# --agent codex (Codex reads that dir directly); this script then rsyncs each
# skill into the shared skills/ dir as COPIES so Claude Code sees them too.
# The copies are deliberately NOT tracked by git — a marker-delimited block in
# .gitignore (regenerated on every run) keeps them out of the repo.
# code-review stays Codex-only: it would collide with Claude Code's built-in
# /code-review.
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
MATT_REPO="https://github.com/mattpocock/skills.git"

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
if ! command -v jq >/dev/null 2>&1; then
  warn "jq is required to parse ${LOCK}"
  exit 1
fi
old_matt_list=""
if [ -f "$LOCK" ]; then
  if ! old_matt_list="$(jq -r 'if (.skills // {} | type) != "object" then error("invalid skills lock") else
      [.skills // {} | to_entries[]
        | select(.value | tostring | contains("mattpocock/skills")) | .key]
      | if all(.[]; test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) then .[] else error("invalid skill name") end
    end' "$LOCK" 2>/dev/null)"; then
    warn "invalid ${LOCK}; refusing reconciliation"
    exit 1
  fi
fi
old_matt_list="${old_matt_list//$'\r'/}"

upstream_tmp="$(mktemp -d)"
trap 'rm -rf "$upstream_tmp"' EXIT
if ! git clone --depth 1 --quiet "$MATT_REPO" "$upstream_tmp/repo"; then
  warn "failed to read upstream skill set"
  exit 1
fi
upstream_list="$(find "$upstream_tmp/repo/skills" -name SKILL.md -exec dirname {} \; \
  | while IFS= read -r dir; do basename "$dir"; done | LC_ALL=C sort -u)"
if [ -z "$upstream_list" ] || printf '%s\n' "$upstream_list" | grep -Evq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
  warn "invalid or empty upstream skill set; refusing reconciliation"
  exit 1
fi

info "reconciling with upstream"
if run_skills add mattpocock/skills --skill '*' --agent codex --global --yes; then
  info "mattpocock/skills reconciled"
else
  warn "mattpocock/skills reconciliation failed"
  exit 1
fi

if ! installed_list="$(jq -r '[.skills // {} | to_entries[]
    | select(.value | tostring | contains("mattpocock/skills")) | .key]
  | sort | .[]' "$LOCK" 2>/dev/null)"; then
  warn "invalid ${LOCK} after reconciliation"
  exit 1
fi
installed_list="${installed_list//$'\r'/}"
for name in $upstream_list; do
  if ! printf '%s\n' "$installed_list" | grep -Fxq "$name" \
    || [ ! -f "${AGENTS_SKILLS_DIR}/${name}/SKILL.md" ]; then
    warn "reconciliation incomplete: missing ${name}"
    exit 1
  fi
done

stale_names=()
for name in $old_matt_list; do
  printf '%s\n' "$upstream_list" | grep -Fxq "$name" || stale_names+=("$name")
done
if [ "${#stale_names[@]}" -gt 0 ]; then
  if ! run_skills remove "${stale_names[@]}" --global --agent codex --yes; then
    warn "failed to remove upstream-deleted skills"
    exit 1
  fi
  stale_json="$(printf '%s\n' "${stale_names[@]}" | jq -R . | jq -s .)"
  lock_tmp="${LOCK}.tmp.$$"
  if ! jq --argjson stale "$stale_json" \
    'reduce $stale[] as $name (. ; del(.skills[$name]))' "$LOCK" > "$lock_tmp"; then
    rm -f "$lock_tmp"
    warn "failed to remove stale entries from ${LOCK}"
    exit 1
  fi
  mv "$lock_tmp" "$LOCK"
  for name in "${stale_names[@]}"; do
    rm -rf "${AGENTS_SKILLS_DIR:?}/${name}"
  done
  info "removed upstream-deleted skills: ${stale_names[*]}"
fi

section "Syncing copies for Claude Code"
matt_list="$upstream_list"

# code-review stays Codex-only (collides with Claude Code's built-in), so it is
# filtered out before the sync; the rest are owned by matt-skills. Orphan
# cleanup keys on that owner, leaving cli-skills' copies in skills/ untouched.
sync_names=()
for name in $matt_list; do
  [ "$name" = "$MATT_CLAUDE_DENY" ] && continue
  sync_names+=("$name")
done
if ! sync_skill_copies matt-skills "$AGENTS_SKILLS_DIR" "$SKILLS_DIR" "$GITIGNORE" \
  ${sync_names[@]+"${sync_names[@]}"}; then
  fail=1
fi
info "synced mattpocock skills into ${SKILLS_DIR} (deny: ${MATT_CLAUDE_DENY})"

[ "$fail" -eq 0 ] || exit 1
section "mattpocock-skills done"
