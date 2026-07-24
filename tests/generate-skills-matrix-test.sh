#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE_ROOT="$TMP_ROOT/repo"
FIXTURE_HOME="$TMP_ROOT/home"
mkdir -p \
  "$FIXTURE_ROOT/scripts" \
  "$FIXTURE_ROOT/skills/upstream-both" \
  "$FIXTURE_ROOT/skills/upstream-claude" \
  "$FIXTURE_ROOT/codex-skills/fork-codex" \
  "$FIXTURE_ROOT/other-skills/marcus/foreign-both" \
  "$FIXTURE_HOME/.agents/skills/upstream-claude" \
  "$FIXTURE_HOME/.agents/skills/fork-codex"
cp "$REPO_ROOT/scripts/generate-skills-matrix.py" "$FIXTURE_ROOT/scripts/"
cat > "$FIXTURE_ROOT/scripts/update-skill-topology.sh" <<'BASH'
#!/usr/bin/env bash
cat <<'JSON'
{
  "status": "drift",
  "errors": [],
  "plan": [
    {"sourceId": "repo-claude", "skill": "upstream-both", "destinations": ["claude", "codex"]},
    {"sourceId": "repo-claude", "skill": "upstream-claude", "destinations": ["claude"]},
    {"sourceId": "repo-codex", "skill": "fork-codex", "destinations": ["codex"]},
    {"sourceId": "khazix-skills", "skill": "foreign-both", "destinations": ["claude", "codex"]}
  ]
}
JSON
exit 1
BASH
chmod +x "$FIXTURE_ROOT/scripts/update-skill-topology.sh"
printf '%s\n' 'fixture upstream both' > "$FIXTURE_ROOT/skills/upstream-both/SKILL.md"
printf '%s\n' 'fixture upstream claude' > "$FIXTURE_ROOT/skills/upstream-claude/SKILL.md"
printf '%s\n' 'fixture fork codex' > "$FIXTURE_ROOT/codex-skills/fork-codex/SKILL.md"
printf '%s\n' 'fixture staged foreign' > "$FIXTURE_ROOT/other-skills/marcus/foreign-both/SKILL.md"
cp "$FIXTURE_ROOT/skills/upstream-claude/SKILL.md" "$FIXTURE_HOME/.agents/skills/upstream-claude/SKILL.md"
cp "$FIXTURE_ROOT/codex-skills/fork-codex/SKILL.md" "$FIXTURE_HOME/.agents/skills/fork-codex/SKILL.md"
cat > "$FIXTURE_ROOT/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {"upstream-both": ["claude", "codex"]}
    },
    {
      "id": "repo-codex",
      "classification": "repo-owned",
      "defaultDestinations": ["codex"],
      "overrides": {}
    },
    {
      "id": "khazix-skills",
      "classification": "source-only",
      "defaultDestinations": ["claude", "codex"],
      "overrides": {}
    }
  ]
}
JSON

HOME="$FIXTURE_HOME" python3 "$FIXTURE_ROOT/scripts/generate-skills-matrix.py" > "$TMP_ROOT/matrix.md"

rg -F '| Skill | Source | Type | Claude | Codex | ~Tokens |' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `upstream-both` \| steipete/agent-scripts \| skill \| Y \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `upstream-claude` \| steipete/agent-scripts \| skill \| Y \| N \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `fork-codex` \| marcuslannister/agent-scripts \| skill \| N \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `foreign-both` \| khazix-skills \| skill \| Y \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| Availability | Claude | Codex |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Total | 3 | 3 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Shared | 2 | 2 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Agent-only | 1 | 1 |' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| State | Claude | Codex |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Enabled | 0 | 0 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Disabled | 0 | 0 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Always-on | 3 | 3 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Total | 3 | 3 |' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| `steipete/agent-scripts` | https://github.com/steipete/agent-scripts |' "$TMP_ROOT/matrix.md" >/dev/null

echo "generate-skills-matrix tests passed"
