#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/repo"
HOME_ROOT="$TMP_ROOT/home"
mkdir -p \
  "$FIXTURE/agent-tooling" \
  "$FIXTURE/skills/upstream-existing" \
  "$FIXTURE/codex-skills/codex-new" \
  "$FIXTURE/other-skills/alpha/staged-existing" \
  "$FIXTURE/other-skills/alpha/staged-new" \
  "$HOME_ROOT/.claude/plugins/cache/example/plugin-existing/1.0.0"

cp "$REPO_ROOT/agent-tooling/generate-skills-matrix.py" "$FIXTURE/agent-tooling/"

for path in \
  skills/upstream-existing \
  codex-skills/codex-new \
  other-skills/alpha/staged-existing \
  other-skills/alpha/staged-new; do
  printf '%s\n' "fixture $path" > "$FIXTURE/$path/SKILL.md"
done
printf '%s\n' 'fixture plugin' \
  > "$HOME_ROOT/.claude/plugins/cache/example/plugin-existing/1.0.0/SKILL.md"
cat > "$FIXTURE/other-skills/alpha/.source.json" <<'JSON'
{"repo":"https://github.com/example/alpha-skills.git","commit":"abc","syncedAt":"2026-07-28T00:00:00Z"}
JSON
cat > "$HOME_ROOT/.claude/plugins/known_marketplaces.json" <<'JSON'
{"example":{"source":{"repo":"https://github.com/example/plugin-existing.git"}}}
JSON
cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
# Skills matrix

Hand-edit Claude/Codex selections; regeneration preserves them.

## Counts

| Availability | Claude | Codex |
|---|---|---|
| Total | 999 | 999 |

| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `plugin-existing` | old/plugin-source | plugin | Y | N | ~1 |
| `staged-existing` | old/staged-source | skill | Y | Y | ~1 |
| `stale-selected` | old/stale-source | skill | N | Y | ~1 |
| `upstream-existing` | old/upstream-source | skill | Y | N | ~1 |

<!-- total=999 -->

## Enable-state

stale

## Repos

stale
MARKDOWN

HOME="$HOME_ROOT" python3 "$FIXTURE/agent-tooling/generate-skills-matrix.py" \
  > "$FIXTURE/generated.md"

# Existing selections remain verbatim even when attribution is refreshed.
rg '^\| `plugin-existing` \| example/plugin-existing \| plugin \| Y \| N \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `staged-existing` \| example/alpha-skills \| skill \| Y \| Y \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `upstream-existing` \| steipete/agent-scripts \| skill \| Y \| N \|' \
  "$FIXTURE/generated.md" >/dev/null

# Newly discovered rows are appended unselected; stale rows remain actionable.
rg '^\| `codex-new` \| marcuslannister/agent-scripts \| skill \| N \| N \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `staged-new` \| example/alpha-skills \| skill \| N \| N \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `stale-selected` \| old/stale-source \| skill \| N \| Y \|' \
  "$FIXTURE/generated.md" >/dev/null

# Derived sections are recomputed from preserved selections.
rg -F '| Total | 3 | 2 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Shared | 1 | 1 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Agent-only | 2 | 1 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| `example/alpha-skills` | https://github.com/example/alpha-skills |' \
  "$FIXTURE/generated.md" >/dev/null

echo "generate-skills-matrix selection-preservation tests passed"
