#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
exec node "$SCRIPT_DIR/distribution-topology/topology.mjs" "$@"
