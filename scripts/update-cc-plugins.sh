#!/usr/bin/env bash
set -euo pipefail

# Compatibility entrypoint. Manifest topology owns plugin inventory and mutation.
exec "${BASH_SOURCE[0]%/*}/update-skill-topology.sh" "$@"
