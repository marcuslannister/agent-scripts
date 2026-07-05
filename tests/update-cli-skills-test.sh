#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/update-cli-skills.sh"

# skills@latest currently documents '*' for remove --agent, but rejects it.
if grep -Eq -- "--agent[[:space:]]+['\"]?\\*" "$SCRIPT"; then
  echo "FAIL: update-cli-skills.sh must not pass --agent '*' to skills remove" >&2
  exit 1
fi

grep -F 'SKILLS_CLI_AGENT=codex' "$SCRIPT" >/dev/null
grep -F 'run_skills remove $waza_list --global --agent "$SKILLS_CLI_AGENT" --yes' "$SCRIPT" >/dev/null

echo "update-cli-skills tests passed"
