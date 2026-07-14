#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO_ROOT/scripts/test-skill-topology-policy"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

"$POLICY" "$REPO_ROOT"

FIXTURE="$TMP_ROOT/repo"
mkdir -p "$FIXTURE/scripts/distribution-topology"
cp "$REPO_ROOT/scripts/update-all.sh" "$FIXTURE/scripts/"
cp "$REPO_ROOT/scripts/update-agents.sh" "$FIXTURE/scripts/"
cp "$REPO_ROOT/scripts/update-skill-topology.sh" "$FIXTURE/scripts/"
cp "$REPO_ROOT/skill-topology.json" "$FIXTURE/"
cp "$REPO_ROOT/scripts/distribution-topology/registry.json" \
  "$FIXTURE/scripts/distribution-topology/"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FIXTURE/scripts/update-repo-skills.sh"
jq '(.sources[] | select(.id == "repo-claude") | .defaultDestinations) = ["claude", "codex"]' \
  "$FIXTURE/skill-topology.json" > "$FIXTURE/manifest.tmp"
mv "$FIXTURE/manifest.tmp" "$FIXTURE/skill-topology.json"

if "$POLICY" "$FIXTURE" > "$TMP_ROOT/out" 2>&1; then
  echo "FAIL: cutover policy accepted the old bulk-publication policy" >&2
  exit 1
fi
grep -F 'unexpected public updater: update-repo-skills.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'repo-claude must default only to Claude' "$TMP_ROOT/out" >/dev/null

echo "topology cutover policy tests passed"
