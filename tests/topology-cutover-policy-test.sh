#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO_ROOT/agent-tooling/test-skill-topology-policy"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

"$POLICY" "$REPO_ROOT"

FIXTURE="$TMP_ROOT/repo"
mkdir -p "$FIXTURE/agent-tooling"
cp "$REPO_ROOT/agent-tooling/update-all.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/update-agents.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/sync-skill-surfaces.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/skill-topology.json" "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FIXTURE/agent-tooling/update-repo-skills.sh"
printf '%s\n' '#!/usr/bin/env bash' \
  'exec "$(dirname "$0")/distribution-topology/topology.sh" "$@"' \
  > "$FIXTURE/agent-tooling/sync-skills.sh"
printf '%s\n' 'TOPOLOGY_PHASE="${TOPOLOGY_PHASE:-full}"' \
  >> "$FIXTURE/agent-tooling/distribution-topology/topology.sh"
jq '(.sources[] | select(.id == "repo-claude") | .overrides) = {}' \
  "$FIXTURE/agent-tooling/skill-topology.json" > "$FIXTURE/manifest.tmp"
mv "$FIXTURE/manifest.tmp" "$FIXTURE/agent-tooling/skill-topology.json"

if "$POLICY" "$FIXTURE" > "$TMP_ROOT/out" 2>&1; then
  echo "FAIL: cutover policy accepted the old bulk-publication policy" >&2
  exit 1
fi
grep -F 'unexpected public updater: update-repo-skills.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'unexpected public acquire command: sync-skills.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'acquire topology core must not contain phase gating' "$TMP_ROOT/out" >/dev/null
grep -F 'topology manifest must contain acquire source policy only' "$TMP_ROOT/out" >/dev/null

echo "topology cutover policy tests passed"
