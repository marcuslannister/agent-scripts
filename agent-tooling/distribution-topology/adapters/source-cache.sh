# Machine-local cache for read-only upstream clones.
#
# Discovery used to clone every plugin repository into the throwaway discovery
# root, so each run — including a --plugins-only run on a secondary machine —
# paid a cold clone per source before it could report anything. The cache keeps
# one shallow clone per source under $HOME and refreshes it in place. It is
# per-machine state that git never carries, and it holds no local edits: any
# refresh failure discards the directory and clones again.

source_cache_dir() { # home source_id
  printf '%s/.cache/agent-scripts/source-clones/%s' "$1" "$2"
}

refresh_cached_clone() { # cache_dir repo_url
  local cache_dir="$1"
  local repo_url="$2"
  if [ -d "$cache_dir/.git" ] \
    && [ "$(git -C "$cache_dir" remote get-url origin 2>/dev/null)" = "$repo_url" ] \
    && git -C "$cache_dir" pull --ff-only --quiet >/dev/null 2>&1; then
    return 0
  fi
  rm -rf -- "$cache_dir"
  mkdir -p -- "$(dirname "$cache_dir")"
  git clone --depth 1 --quiet "$repo_url" "$cache_dir"
}
