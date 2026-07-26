#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
export TOPOLOGY_PHASE=distribute
export TOPOLOGY_COMMAND_NAME=sync-skill-surfaces.sh
if [ "$(trap -p INT)" = "trap -- '' SIGINT" ]; then
  exec ruby -e 'Signal.trap("INT", "DEFAULT"); Signal.trap("TERM", "DEFAULT"); exec(*ARGV)' \
    "$SCRIPT_DIR/distribution-topology/topology.sh" "$@"
fi
exec "$SCRIPT_DIR/distribution-topology/topology.sh" "$@"
