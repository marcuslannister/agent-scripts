#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: $(basename "$0") <vm-name> [--env KEY=VALUE ...] <openclaw-args...>" >&2
  exit 64
fi

vm=$1
shift

env_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || prl_windows_die "--env requires KEY=VALUE"
      env_args+=("$2")
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -gt 0 ]] || prl_windows_die "missing openclaw args"

prl_windows_require_prlctl
prl_windows_run_openclaw_env "$vm" "${env_args[@]}" "$@"
