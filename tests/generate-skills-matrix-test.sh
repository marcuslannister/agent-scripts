#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE_ROOT="$TMP_ROOT/repo"
FIXTURE_HOME="$TMP_ROOT/home"
mkdir -p \
  "$FIXTURE_ROOT/scripts" \
  "$FIXTURE_ROOT/agent-tooling" \
  "$FIXTURE_ROOT/skills/upstream-both" \
  "$FIXTURE_ROOT/skills/upstream-claude" \
  "$FIXTURE_ROOT/codex-skills/fork-codex" \
  "$FIXTURE_ROOT/other-skills/khazix/foreign-both" \
  "$FIXTURE_ROOT/other-skills/matt/ask-matt" \
  "$FIXTURE_HOME"
cp "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" "$FIXTURE_ROOT/scripts/"
mkdir -p "$FIXTURE_ROOT/agent-tooling/distribution-topology"
cat > "$FIXTURE_ROOT/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "matt-skills",
    "matrixSource": "mattpocock/skills"
  }
]
JSON
cat > "$FIXTURE_ROOT/plan.json" <<'JSON'
[
  {"sourceId": "repo-claude", "skill": "upstream-both", "destinations": ["claude", "codex"]},
  {"sourceId": "repo-claude", "skill": "upstream-claude", "destinations": ["claude"]},
  {"sourceId": "repo-codex", "skill": "fork-codex", "destinations": ["codex"]},
  {"sourceId": "khazix-skills", "skill": "foreign-both", "destinations": ["claude", "codex"]},
  {"sourceId": "matt-skills", "skill": "ask-matt", "destinations": ["codex"]}
]
JSON
printf '%s\n' 'fixture upstream both' > "$FIXTURE_ROOT/skills/upstream-both/SKILL.md"
printf '%s\n' 'fixture upstream claude' > "$FIXTURE_ROOT/skills/upstream-claude/SKILL.md"
printf '%s\n' 'fixture fork codex' > "$FIXTURE_ROOT/codex-skills/fork-codex/SKILL.md"
printf '%s\n' 'fixture staged foreign' > "$FIXTURE_ROOT/other-skills/khazix/foreign-both/SKILL.md"
printf '%s\n' 'fixture staged matt skill' > "$FIXTURE_ROOT/other-skills/matt/ask-matt/SKILL.md"
HOME="$FIXTURE_HOME" SKILL_MATRIX_PLAN_PATH="$FIXTURE_ROOT/plan.json" \
  python3 "$FIXTURE_ROOT/scripts/generate-skills-matrix.py" > "$TMP_ROOT/matrix.md"

rg -F 'mutable — retoggling' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Skill | Source | Type | Claude | Codex | ~Tokens |' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `upstream-both` \| steipete/agent-scripts \| skill \| Y \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `upstream-claude` \| steipete/agent-scripts \| skill \| Y \| N \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `fork-codex` \| marcuslannister/agent-scripts \| skill \| N \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `foreign-both` \| khazix-skills \| skill \| Y \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null
rg '^\| `ask-matt` \| mattpocock/skills \| skill \| N \| Y \| ~[0-9]+ \|$' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| Availability | Claude | Codex |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Total | 3 | 4 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Shared | 2 | 2 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Agent-only | 1 | 2 |' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| State | Claude | Codex |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Enabled | 0 | 0 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Disabled | 0 | 0 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Always-on | 3 | 4 |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| Total | 3 | 4 |' "$TMP_ROOT/matrix.md" >/dev/null

rg -F '| `steipete/agent-scripts` | https://github.com/steipete/agent-scripts |' "$TMP_ROOT/matrix.md" >/dev/null
rg -F '| `mattpocock/skills` | https://github.com/mattpocock/skills |' "$TMP_ROOT/matrix.md" >/dev/null

echo "generate-skills-matrix tests passed"
