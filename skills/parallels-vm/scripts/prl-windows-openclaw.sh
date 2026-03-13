#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

if [[ $# -lt 2 ]]; then
  echo "usage: $(basename "$0") <vm-name> [--prefix <guest-prefix>] [--env KEY=VALUE ...] <openclaw-args...>" >&2
  exit 64
fi

vm=$1
shift

prefix=
env_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || prl_windows_die "--prefix requires a guest prefix path"
      prefix=$2
      shift 2
      ;;
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
if [[ -n "$prefix" ]]; then
  if [[ ${#env_args[@]} -gt 0 ]]; then
    prl_windows_run_openclaw_prefix_env "$vm" "$prefix" "${env_args[@]}" "$@"
  else
    prl_windows_run_openclaw_prefix_env "$vm" "$prefix" "$@"
  fi
else
  if [[ ${#env_args[@]} -gt 0 ]]; then
    prl_windows_run_openclaw_env "$vm" "${env_args[@]}" "$@"
  else
    prl_windows_run_openclaw_env "$vm" "$@"
  fi
fi
