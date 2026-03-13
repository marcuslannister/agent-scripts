#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-macos-lib.sh
source "$SCRIPT_DIR/prl-macos-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> <guest-repo-dir> [--env KEY=VALUE ...] [--] <vitest-args...>" >&2
  exit 64
}

[[ $# -ge 3 ]] || usage

vm=$1
repo_dir=$2
shift 2

env_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || prl_die "--env requires KEY=VALUE"
      env_args+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -gt 0 ]] || prl_die "missing vitest args"

prl_require_prlctl
prl_require_node

# Keep guest vitest invocations consistent:
# - `pnpm exec vitest`, not bare `pnpm vitest`
# - force `--root <repo>` so relative test paths resolve predictably
prl_run_pnpm_env "$vm" "$repo_dir" "${env_args[@]}" exec vitest --root "$repo_dir" "$@"
