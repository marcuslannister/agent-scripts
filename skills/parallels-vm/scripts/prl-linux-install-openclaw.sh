#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-linux-lib.sh
source "$SCRIPT_DIR/prl-linux-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--version <version|tag>] [--install-url <url>] [--profile <name>] [--state-dir <dir>] [--method npm|git] [--verbose] [--keep-installer]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

version=latest
install_url=https://openclaw.ai/install.sh
method=npm
verbose=0
keep_installer=0
profile=
state_dir=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version=${2:?missing version}
      shift 2
      ;;
    --install-url)
      install_url=${2:?missing install url}
      shift 2
      ;;
    --profile)
      profile=${2:?missing profile}
      shift 2
      ;;
    --state-dir)
      state_dir=${2:?missing state dir}
      shift 2
      ;;
    --method)
      method=${2:?missing method}
      shift 2
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    --keep-installer)
      keep_installer=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

case "$method" in
  npm|git) ;;
  *) prl_linux_die "invalid --method: $method" ;;
esac

prl_linux_require_prlctl

installer="/tmp/openclaw-install-$(date +%s).sh"
prl_linux_download_to_guest "$vm" "$install_url" "$installer"

env_args=("OPENCLAW_NO_ONBOARD=1")
[[ -n "$profile" ]] && env_args+=("OPENCLAW_PROFILE=$profile")
[[ -n "$state_dir" ]] && env_args+=("OPENCLAW_STATE_DIR=$state_dir")

install_cmd="export NPM_CONFIG_PREFIX=\"\$HOME/.local\";"
local_env_arg=
for local_env_arg in "${env_args[@]}"; do
  install_cmd+=" export $local_env_arg;"
done
install_cmd+=" /bin/bash \"$installer\" --version \"$version\" --no-onboard --no-prompt --$method"
if [[ "$verbose" == "1" ]]; then
  install_cmd+=" --verbose"
fi

prl_linux_exec_sh "$vm" "$install_cmd"

if [[ "$keep_installer" != "1" ]]; then
  prlctl exec "$vm" --current-user /bin/rm -f "$installer" >/dev/null 2>&1 || true
fi

prl_linux_run_openclaw_env "$vm" "${env_args[@]}" --version
