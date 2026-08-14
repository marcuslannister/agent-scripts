#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${AGENT_SCRIPTS_UPSTREAM_MANIFEST:-$SCRIPT_DIR/upstream-overlay.json}"
UPSTREAM_URL="${AGENT_SCRIPTS_UPSTREAM_URL:-https://github.com/steipete/agent-scripts}"
UPSTREAM_BRANCH="${AGENT_SCRIPTS_UPSTREAM_BRANCH:-main}"

usage() {
  printf '%s\n' \
    'Usage: sync-upstream-overlay.sh [--check]' \
    '' \
    'Merge steipete/agent-scripts and restore every upstream path while keeping' \
    'local additions and committed modifications.' \
    '' \
    'Options:' \
    '  --check     Verify the recorded upstream overlay without network access.' \
    '  -h, --help  Show this help and exit.'
}

fail() {
  printf 'upstream overlay: %s\n' "$1" >&2
  exit 1
}

collect_missing_paths() {
  local source_commit="$1"
  local path
  missing_paths=()

  while IFS= read -r -d '' path; do
    if [ ! -e "$REPO_ROOT/$path" ] && [ ! -L "$REPO_ROOT/$path" ]; then
      missing_paths+=("$path")
    fi
  done < <(git -C "$REPO_ROOT" ls-tree -rz --name-only "$source_commit")
}

check_overlay() {
  local source_commit
  local path

  [ -f "$MANIFEST" ] || fail "missing source record: ${MANIFEST#"$REPO_ROOT"/}"
  source_commit="$(jq -er '.commit | strings | select(test("^[0-9a-f]{40}$"))' "$MANIFEST")" \
    || fail "source record has an invalid commit"
  git -C "$REPO_ROOT" cat-file -e "${source_commit}^{commit}" 2>/dev/null \
    || fail "recorded upstream commit is not in local Git history: $source_commit"
  git -C "$REPO_ROOT" merge-base --is-ancestor "$source_commit" HEAD \
    || fail "recorded upstream commit is not merged into HEAD: $source_commit"

  collect_missing_paths "$source_commit"
  if [ "${#missing_paths[@]}" -gt 0 ]; then
    printf 'upstream overlay: missing %d path(s) from %s:\n' \
      "${#missing_paths[@]}" "$source_commit" >&2
    for path in "${missing_paths[@]}"; do
      printf '  %s\n' "$path" >&2
    done
    return 1
  fi

  printf 'Upstream overlay complete at %s (%d paths).\n' \
    "$source_commit" "$(git -C "$REPO_ROOT" ls-tree -r --name-only "$source_commit" | wc -l | tr -d ' ')"
}

mode=sync
case "${1:-}" in
  '') ;;
  --check) mode=check ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    printf 'upstream overlay: unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || {
  usage >&2
  exit 2
}

if [ "$mode" = check ]; then
  check_overlay
  exit 0
fi

[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
  || fail "sync requires a clean worktree"

git -C "$REPO_ROOT" fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
source_commit="$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)"
git -C "$REPO_ROOT" merge --no-edit "$source_commit"

collect_missing_paths "$source_commit"
if [ "${#missing_paths[@]}" -gt 0 ]; then
  git -C "$REPO_ROOT" archive --format=tar "$source_commit" -- "${missing_paths[@]}" \
    | tar -xf - -C "$REPO_ROOT"
fi

manifest_tmp="$(mktemp "${MANIFEST}.tmp.XXXXXX")"
trap 'rm -f "$manifest_tmp"' EXIT
jq -n \
  --arg repository "$UPSTREAM_URL" \
  --arg branch "$UPSTREAM_BRANCH" \
  --arg commit "$source_commit" \
  '{repository: $repository, branch: $branch, commit: $commit}' > "$manifest_tmp"
mv "$manifest_tmp" "$MANIFEST"
trap - EXIT

printf 'Restored %d missing upstream path(s).\n' "${#missing_paths[@]}"
check_overlay
