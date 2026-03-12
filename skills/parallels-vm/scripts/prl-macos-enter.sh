#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") <vm-name>" >&2
  exit 64
fi

exec prlctl enter "$1" --current-user --use-advanced-terminal
