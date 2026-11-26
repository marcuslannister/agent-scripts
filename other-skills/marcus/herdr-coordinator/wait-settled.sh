#!/usr/bin/env bash
# Wait until a Herdr agent has really finished. `herdr agent wait` returns at the first
# pause, and long tasks pause between steps, so require several idle/done checks in a row.
# Usage: wait-settled.sh <agent name> [timeout minutes, default 480]
# Exit: 0 settled (idle/done), 2 blocked, 3 agent gone, 4 timeout, 64 usage.
set -uo pipefail
name="${1:?usage: wait-settled.sh <agent name> [timeout minutes]}"
timeout_min="${2:-480}"
interval="${WAIT_SETTLED_INTERVAL:-45}"
need="${WAIT_SETTLED_CHECKS:-3}"
deadline=$(( $(date +%s) + timeout_min * 60 ))
calm=0
while :; do
  if ! json=$(herdr agent get "$name" 2>/dev/null); then
    echo "$name: gone"; exit 3
  fi
  state=$(printf '%s' "$json" | jq -r '.result.agent.agent_status // "unknown"')
  case "$state" in
    blocked) echo "$name: blocked"; exit 2 ;;
    idle|done) calm=$((calm + 1)) ;;
    *) calm=0 ;;
  esac
  if [ "$calm" -ge "$need" ]; then echo "$name: $state"; exit 0; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then echo "$name: timeout ($state)"; exit 4; fi
  sleep "$interval"
done
