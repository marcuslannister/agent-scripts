#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

COMMAND="$REPO_ROOT/agent-tooling/repair-claude-mem-marker.sh"
CACHE_ROOT="$TMP_ROOT/cache"

make_plugin() { # version package_version
  local version="$1" package_version="$2" root
  root="$CACHE_ROOT/$version"
  mkdir -p "$root"
  printf '{"version":"%s"}\n' "$package_version" > "$root/package.json"
  printf '%s\n' "$root"
}

run() { # extra-args...
  CODEX_MARKER_CACHE_ROOT="$CACHE_ROOT" "$COMMAND" "$@"
}

root_13150="$(make_plugin 13.15.0 13.15.0)"

# Check mode reports a missing marker and makes no change.
set +e
run --check > "$TMP_ROOT/check.out" 2> "$TMP_ROOT/check.err"
check_exit=$?
set -e
test "$check_exit" -eq 1
test ! -e "$root_13150/.install-version"
grep -q 'would write 13.15.0' "$TMP_ROOT/check.out"

# The default action repairs the marker and is idempotent.
run > "$TMP_ROOT/repair.out"
grep -Fxq '{"version":"13.15.0"}' "$root_13150/.install-version"
grep -q 'repaired marker for 13.15.0' "$TMP_ROOT/repair.out"
run > "$TMP_ROOT/second.out"
grep -q 'marker matches 13.15.0' "$TMP_ROOT/second.out"

# A stale marker is replaced with the package version.
printf '%s\n' '{"version":"13.14.0"}' > "$root_13150/.install-version"
run > "$TMP_ROOT/stale.out"
grep -Fxq '{"version":"13.15.0"}' "$root_13150/.install-version"
grep -q 'repaired marker for 13.15.0' "$TMP_ROOT/stale.out"

# Orphaned and malformed cache versions are never repaired.
orphan_root="$(make_plugin 13.15.1 13.15.1)"
touch "$orphan_root/.orphaned_at"
invalid_root="$(make_plugin 13.16.0 not-a-version)"
set +e
run > "$TMP_ROOT/invalid.out" 2> "$TMP_ROOT/invalid.err"
invalid_exit=$?
set -e
test "$invalid_exit" -eq 1
test ! -e "$orphan_root/.install-version"
test ! -e "$invalid_root/.install-version"
grep -q 'package.json has no valid version' "$TMP_ROOT/invalid.err"

echo "repair-claude-mem-marker tests passed"
