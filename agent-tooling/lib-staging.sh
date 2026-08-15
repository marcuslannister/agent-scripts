#!/usr/bin/env bash

# Shared helpers for tracked foreign-skill staging (other-skills/<owner>/) and
# the machine-local source clone cache. Staging is markerless tracked content:
# provenance lives in git history plus each source dir's .source.json, never in
# per-skill copy markers (ADR-0005). Callers must source lib-copies.sh first
# for copy_warn and remove_gitignore_block.

# --- Source clone cache -----------------------------------------------------
# One shallow clone of a read-only upstream repository per source, refreshed in
# place. Per-machine state git never carries; holds no local edits, so any
# refresh failure discards the directory and clones again. Check mode must not
# use it — a preview clones into its own discovery root instead (a --check run
# writes nothing under HOME).

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

# --- Staging trees ----------------------------------------------------------

copy_contents_match() { # source destination
  local source="$1"
  local destination="$2"
  [ -d "$source" ] && [ -d "$destination" ] \
    && diff -qr -x .agent-scripts-copy -x .agent-scripts-copy-source \
      "$source" "$destination" >/dev/null 2>&1
}

install_stage_tree() { # source_dir dest_dir
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    copy_warn "missing source: $src"
    return 1
  fi
  if [ -L "$dst" ]; then
    unlink "$dst" || return 1
  elif [ -e "$dst" ] && [ ! -d "$dst" ]; then
    copy_warn "not a directory or symlink, refusing to replace: $dst"
    return 1
  fi
  mkdir -p "$dst" || return 1
  if [ "${AGENT_SCRIPTS_DISABLE_RSYNC:-0}" != "1" ] && command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${src}/" "${dst}/" || return 1
  else
    # Git Bash on Windows ships no rsync; emulate --delete with a fresh copy.
    rm -rf "$dst" || return 1
    mkdir -p "$dst" || return 1
    cp -R "${src}/." "${dst}/" || return 1
  fi
  rm -f "${dst}/.agent-scripts-copy" "${dst}/.agent-scripts-copy-source"
}

inspect_stage_tree() { # content_source destination
  local content_source="$1"
  local destination="$2"

  if [ -L "$destination" ]; then
    printf 'foreign\tunowned\n'
    return
  fi
  if [ ! -e "$destination" ]; then
    printf 'absent\tmissing\n'
    return
  fi
  if [ ! -d "$destination" ]; then
    printf 'foreign\tunowned\n'
    return
  fi
  if [ -f "$destination/.agent-scripts-copy" ] || [ -f "$destination/.agent-scripts-copy-source" ]; then
    printf 'drift\tlegacy-marker\n'
    return
  fi
  if copy_contents_match "$content_source" "$destination"; then
    printf 'present\tmanaged\n'
  else
    printf 'drift\tcontent-mismatch\n'
  fi
}

write_staging_source_json() { # staging_root repo clone_dir
  local staging_root="$1"
  local repo="$2"
  local clone_dir="$3"
  local commit synced_at

  commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$commit" ]; then
    printf 'unable to read upstream commit: %s\n' "$clone_dir" >&2
    return 1
  fi
  synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$staging_root" || return 1
  jq -n --arg repo "$repo" --arg commit "$commit" --arg syncedAt "$synced_at" \
    '{repo:$repo, commit:$commit, syncedAt:$syncedAt}' > "$staging_root/.source.json"
}

clear_staging_gitignore() { # repo_root owner
  local repo_root="$1"
  local owner="$2"
  local gitignore="$repo_root/.gitignore"
  [ -f "$gitignore" ] || return 0
  remove_gitignore_block "$gitignore" "$owner"
}
