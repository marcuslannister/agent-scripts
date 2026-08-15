#!/usr/bin/env bash
set -euo pipefail

# The executable policy must accept this repo and reject a revival of the
# retired topology engine, its private adapters, or plugin work in acquire.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO_ROOT/agent-tooling/test-skill-topology-policy"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

"$POLICY" "$REPO_ROOT"

FIXTURE="$TMP_ROOT/repo"
TOOLING="$FIXTURE/agent-tooling"
mkdir -p "$TOOLING/distribution-topology" "$FIXTURE/scripts"
while IFS= read -r staging_dir; do
  mkdir -p "$FIXTURE/other-skills/$staging_dir"
done < <(jq -r '.sources[] | select(has("staging")) | .staging' \
  "$REPO_ROOT/agent-tooling/sources.json")
for command in update-all.sh update-agents.sh update-local.sh update-plugins.sh \
  update-skill-topology.sh generate-skills-matrix.sh sync-skill-surfaces.sh \
  sync-upstream-overlay.sh lib-copies.sh lib-staging.sh sources.json; do
  cp "$REPO_ROOT/agent-tooling/$command" "$TOOLING/"
done
cp "$REPO_ROOT/agent-tooling/distribution-topology/distribute.sh" \
  "$REPO_ROOT/agent-tooling/distribution-topology/lock.sh" \
  "$TOOLING/distribution-topology/"
cp "$REPO_ROOT/scripts/sync-skills" "$FIXTURE/scripts/"

# Sanity: the copied tree passes before it is broken.
"$POLICY" "$FIXTURE" >/dev/null

# Revive the engine, an adapter, the manifest, a stray public updater, plugin
# work inside acquire, and the old symlink mirror.
mkdir -p "$TOOLING/distribution-topology/adapters"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TOOLING/distribution-topology/topology.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TOOLING/distribution-topology/adapters/plugin-both.sh"
printf '%s\n' '{"version":1,"sources":[]}' > "$TOOLING/skill-topology.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TOOLING/update-repo-skills.sh"
printf '%s\n' 'codex plugin marketplace upgrade claude-mem-local' >> "$TOOLING/update-skill-topology.sh"
printf '%s\n' 'CLAUDE_ROOT="$HOME/.claude/skills"' 'ln -sfn a b' >> "$FIXTURE/scripts/sync-skills"

if "$POLICY" "$FIXTURE" > "$TMP_ROOT/out" 2>&1; then
  echo "FAIL: policy accepted the retired topology engine" >&2
  exit 1
fi
grep -F 'retired topology module remains: topology.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'retired private-adapter directory remains' "$TMP_ROOT/out" >/dev/null
grep -F 'retired topology manifest remains' "$TMP_ROOT/out" >/dev/null
grep -F 'unexpected public updater: update-repo-skills.sh' "$TMP_ROOT/out" >/dev/null
grep -F 'acquire must not run native plugin commands' "$TMP_ROOT/out" >/dev/null
grep -F 'scripts/sync-skills must be a retired stub' "$TMP_ROOT/out" >/dev/null

# Deleting the upstream path is rejected too (ADR-0008).
rm -f "$FIXTURE/scripts/sync-skills"
if "$POLICY" "$FIXTURE" > "$TMP_ROOT/deleted.out" 2>&1; then
  echo "FAIL: policy accepted a deleted upstream path" >&2
  exit 1
fi
grep -F 'upstream path scripts/sync-skills must not be deleted' "$TMP_ROOT/deleted.out" >/dev/null

echo "topology cutover policy tests passed"
