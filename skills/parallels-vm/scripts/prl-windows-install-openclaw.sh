#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--version <version|tag>] [--install-url <url>] [--method npm|git] [--git-dir <dir>] [--with-onboard]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

version=latest
install_url=https://openclaw.ai/install.ps1
method=npm
git_dir=
no_onboard=1

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
    --method)
      method=${2:?missing method}
      shift 2
      ;;
    --git-dir)
      git_dir=${2:?missing git dir}
      shift 2
      ;;
    --with-onboard)
      no_onboard=0
      shift
      ;;
    *)
      usage
      ;;
  esac
done

case "$method" in
  npm|git) ;;
  *) prl_windows_die "invalid --method: $method" ;;
esac

prl_windows_require_prlctl

script=$(prl_windows_build_install_script "$install_url" "$version" "$method" "$git_dir" "$no_onboard")
raw="$(prl_windows_exec_ps_script "$vm" "$script" 2>&1)"
cleaned="$(printf '%s\n' "$raw" | prl_windows_strip_clixml)"
if [[ -n "${cleaned//$'\n'/}" ]]; then
  printf '%s\n' "$cleaned" >&2
fi

"$SCRIPT_DIR/prl-windows-openclaw.sh" "$vm" --version
