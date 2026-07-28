#!/usr/bin/env bash
set -euo pipefail

action="${1:?action required}"
home="${2:?home required}"
surface="$home/.agents/skills"

guard_surface_root() {
  if [ -L "$surface" ]; then
    printf 'refusing symlinked skill surface root: %s\n' "$surface" >&2
    return 1
  fi
}

case "$action" in
  inspect)
    [ ! -L "$surface" ] || printf 'root-symlink\n'
    ;;
  reconcile|verify)
    guard_surface_root
    ;;
  *)
    printf 'unknown Codex-root hygiene action: %s\n' "$action" >&2
    exit 2
    ;;
esac
