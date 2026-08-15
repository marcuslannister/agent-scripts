#!/usr/bin/env bash
set -euo pipefail

# Cached upstream clones: discovery must refresh one machine-local clone per
# source instead of paying a cold clone on every run. Regression for
# "Discovering sources" stalling a --plugins-only run behind four full clones.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

UPSTREAM="$TMP_ROOT/upstream"
OTHER="$TMP_ROOT/other"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$UPSTREAM" "$OTHER" "$HOME_DIR"

seed_repo() { # path marker
  git -C "$1" init -q
  git -C "$1" config user.email tests@example.com
  git -C "$1" config user.name tests
  printf '%s\n' "$2" > "$1/marker"
  git -C "$1" add marker
  git -C "$1" commit -qm "seed $2"
}

seed_repo "$UPSTREAM" first
seed_repo "$OTHER" other

source "$REPO_ROOT/agent-tooling/distribution-topology/adapters/source-cache.sh"

CACHE="$(source_cache_dir "$HOME_DIR" waza)"
[ "$CACHE" = "$HOME_DIR/.cache/agent-scripts/source-clones/waza" ] \
  || { echo "unexpected cache path: $CACHE" >&2; exit 1; }

# First refresh clones the source.
refresh_cached_clone "$CACHE" "$UPSTREAM"
[ "$(cat "$CACHE/marker")" = first ] || { echo "cache missing upstream content" >&2; exit 1; }

# Second refresh reuses the clone: the sentinel survives and new commits arrive.
printf 'reused\n' > "$CACHE/.cache-sentinel"
printf '%s\n' second > "$UPSTREAM/marker"
git -C "$UPSTREAM" commit -qam second
refresh_cached_clone "$CACHE" "$UPSTREAM"
[ -f "$CACHE/.cache-sentinel" ] || { echo "cache was re-cloned instead of refreshed" >&2; exit 1; }
[ "$(cat "$CACHE/marker")" = second ] || { echo "cache did not pick up the new commit" >&2; exit 1; }

# A cache pointing at a different remote is discarded, not reused.
refresh_cached_clone "$CACHE" "$OTHER"
[ ! -e "$CACHE/.cache-sentinel" ] || { echo "stale remote cache was reused" >&2; exit 1; }
[ "$(cat "$CACHE/marker")" = other ] || { echo "cache did not follow the new remote" >&2; exit 1; }

# An unusable cache directory is replaced rather than failing discovery.
rm -rf "$CACHE/.git"
printf 'debris\n' > "$CACHE/debris"
refresh_cached_clone "$CACHE" "$UPSTREAM"
[ ! -e "$CACHE/debris" ] || { echo "corrupt cache was not rebuilt" >&2; exit 1; }
[ "$(cat "$CACHE/marker")" = second ] || { echo "rebuilt cache has wrong content" >&2; exit 1; }

echo "topology source cache tests passed"
