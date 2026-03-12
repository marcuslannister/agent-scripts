#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $(basename "$0") <vm-name> <guest-repo-dir> <pnpm-args...>" >&2
  exit 64
fi

vm=$1
shift
repo_dir=$1
shift

exec prlctl exec "$vm" --current-user \
  /usr/bin/env \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  /opt/homebrew/bin/node \
  /opt/homebrew/lib/node_modules/pnpm/bin/pnpm.cjs \
  -C "$repo_dir" \
  "$@"
