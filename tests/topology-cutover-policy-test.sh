#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO_ROOT/agent-tooling/test-skill-topology-policy"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

"$POLICY" "$REPO_ROOT"

FIXTURE="$TMP_ROOT/repo"
mkdir -p "$FIXTURE/agent-tooling/distribution-topology"
cp "$REPO_ROOT/agent-tooling/update-all.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/update-agents.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/skill-topology.json" "$FIXTURE/agent-tooling/"
cp "$REPO_ROOT/agent-tooling/distribution-topology/registry.json" \
  "$FIXTURE/agent-tooling/distribution-topology/"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FIXTURE/agent-tooling/update-repo-skills.sh"
jq '(.sources[] | select(.id == "repo-claude") | .defaultDestinations) = ["claude", "codex"]' \
  "$FIXTURE/agent-tooling/skill-topology.json" > "$FIXTURE/manifest.tmp"
mv "$FIXTURE/manifest.tmp" "$FIXTURE/agent-tooling/skill-topology.json"

if "$POLICY" "$FIXTURE" > "$TMP_ROOT/out" 2>&1; then
  echo "FAIL: cutover policy accepted the old bulk-publication policy" >&2
  exit 1
fi
grep -F 'unexpected public updater: update-repo-skills.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'repo-claude must default only to Claude' "$TMP_ROOT/out" >/dev/null

echo "topology cutover policy tests passed"
