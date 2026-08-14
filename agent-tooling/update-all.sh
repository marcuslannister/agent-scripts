#!/usr/bin/env bash
set -uo pipefail

# Top-level updater: agent CLIs, acquire, matrix refresh, then offline distribute.
# Runs every update step (no fail-fast), prints a summary, and can explicitly
# validate, commit, push, and pull the resulting tracked changes with --ship.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

section()     { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
info()        { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn()        { printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2; }
status_line() { # name code
  if [ "$2" -eq 0 ]; then
    printf '\033[0;32m✓\033[0m %s\n' "$1"
  else
    printf '\033[0;31m✗\033[0m %s\n' "$1"
  fi
}

usage() {
  printf '%s\n' \
    'Usage: update-all.sh [--ship]' \
    '' \
    'Update agent CLIs, acquire staged skills, refresh the skills matrix,' \
    'and distribute selected skills.' \
    '' \
    'Options:' \
    '  --ship     Require a clean worktree, validate and commit tracked changes,' \
    '             then push and pull the current branch.' \
    '  -h, --help Show this help and exit.'
}

ship=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done
for arg in "$@"; do
  case "$arg" in
    --ship) ship=1 ;;
    *)
      warn "unknown option: $arg"
      printf 'Run update-all.sh --help for usage.\n' >&2
      exit 2
      ;;
  esac
done

require_clean_worktree() {
  local changes
  if ! changes="$(git -C "$REPO_ROOT" status --porcelain)"; then
    warn "could not inspect the Git worktree"
    return 1
  fi
  if [ -n "$changes" ]; then
    warn "--ship requires a clean worktree before updates run"
    printf '%s\n' "$changes" >&2
    return 1
  fi
}

prepare_ship() {
  section "Preparing ship"
  if ! command -v git >/dev/null 2>&1 \
    || ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "--ship requires this script to run from a Git repository"
    return 1
  fi
  require_clean_worktree || return 1
  if ! git -C "$REPO_ROOT" pull --ff-only; then
    warn "could not fast-forward the current branch before updating"
    return 1
  fi
}

record_changelog() {
  local changelog="$REPO_ROOT/CHANGELOG.md"
  local changelog_tmp source_path source_name source_commit
  local source_revisions=""
  local entry

  [ -f "$changelog" ] || {
    warn "missing changelog: $changelog"
    return 1
  }

  while IFS= read -r source_path; do
    [ -n "$source_path" ] || continue
    source_name="${source_path#other-skills/}"
    source_name="${source_name%%/*}"
    source_commit="$(jq -r '.commit // empty' "$REPO_ROOT/$source_path")"
    [ -n "$source_commit" ] || continue
    source_revisions+="${source_revisions:+, }$source_name ${source_commit:0:7}"
  done < <(git -C "$REPO_ROOT" diff --name-only -- \
    ':(glob)other-skills/*/.source.json')

  if [ -n "$source_revisions" ]; then
    entry="- Refreshed staged third-party skills ($source_revisions) and regenerated the selection-preserving skills matrix."
  else
    entry="- Refreshed tracked skills and regenerated the selection-preserving skills matrix."
  fi

  changelog_tmp="$(mktemp "$changelog.tmp.XXXXXX")" || return 1
  if ! awk -v entry="$entry" '
      !inserted && $0 == "## Unreleased" {
        print
        print ""
        print entry
        print ""
        inserted=1
        skip_blank=1
        next
      }
      skip_blank && $0 == "" { skip_blank=0; next }
      { skip_blank=0; print }
      END { if (!inserted) exit 1 }
    ' "$changelog" > "$changelog_tmp"; then
    rm -f "$changelog_tmp"
    warn "could not add the skill refresh to the Unreleased changelog"
    return 1
  fi
  mv "$changelog_tmp" "$changelog"
  info "changelog: ${entry#- }"
}

ship_changes() {
  local changes

  section "Validating ship"
  if ! "$SCRIPT_DIR/verify.sh"; then
    warn "verification failed; changes were not committed or pushed"
    return 1
  fi

  changes="$(git -C "$REPO_ROOT" status --porcelain)" || return 1
  section "Shipping skill refresh"
  if [ -z "$changes" ]; then
    info "no tracked changes to ship"
    git -C "$REPO_ROOT" status -sb
    return 0
  fi

  record_changelog || return 1
  git -C "$REPO_ROOT" diff --check || return 1
  git -C "$REPO_ROOT" add -A || return 1
  if git -C "$REPO_ROOT" diff --cached --quiet; then
    info "no staged changes to ship"
    return 0
  fi
  git -C "$REPO_ROOT" diff --cached --check || return 1
  git -C "$REPO_ROOT" commit -m "chore: refresh staged skills" || return 1
  git -C "$REPO_ROOT" push || return 1
  git -C "$REPO_ROOT" pull --ff-only || return 1

  changes="$(git -C "$REPO_ROOT" status --porcelain)" || return 1
  if [ -n "$changes" ]; then
    warn "ship completed with remaining worktree changes"
    printf '%s\n' "$changes" >&2
    return 1
  fi
  git -C "$REPO_ROOT" status -sb
}

if [ "$ship" -eq 1 ]; then
  prepare_ship || exit 1
fi

agents_status=0
acquire_status=0
matrix_status=0
distribute_status=0

section "Updating agent CLIs"
"$SCRIPT_DIR/update-agents.sh" || agents_status=$?

section "Acquiring skill topology"
"$SCRIPT_DIR/update-skill-topology.sh" || acquire_status=$?

section "Refreshing skills matrix"
"$SCRIPT_DIR/generate-skills-matrix.sh" > "$SCRIPT_DIR/skills-matrix.md.tmp" \
  && mv "$SCRIPT_DIR/skills-matrix.md.tmp" "$SCRIPT_DIR/skills-matrix.md" \
  || matrix_status=$?

section "Distributing skill surfaces"
"$SCRIPT_DIR/sync-skill-surfaces.sh" || distribute_status=$?

section "Summary"
status_line "agent CLIs" "$agents_status"
status_line "skill acquire" "$acquire_status"
status_line "skills matrix" "$matrix_status"
status_line "skill distribute" "$distribute_status"

(( agents_status != 0 || acquire_status != 0 || matrix_status != 0 || distribute_status != 0 )) && exit 1
[ "$ship" -eq 0 ] || ship_changes || exit 1
exit 0
