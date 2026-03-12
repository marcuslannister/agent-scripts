#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-macos-lib.sh
source "$SCRIPT_DIR/prl-macos-lib.sh"

if [[ $# -ne 3 ]]; then
  echo "usage: $(basename "$0") <vm-name> <url> <guest-path>" >&2
  exit 64
fi

vm=$1
url=$2
guest_path=$3

prl_require_prlctl
prl_download_to_guest "$vm" "$url" "$guest_path"
printf '%s\n' "$guest_path"
