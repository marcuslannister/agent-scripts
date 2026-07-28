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
  "$HOME_ROOT/.claude/plugins/cache/example/plugin-existing/1.0.0" \
  "$HOME_ROOT/plugin-target"

cp "$REPO_ROOT/agent-tooling/generate-skills-matrix.sh" "$FIXTURE/agent-tooling/"

for path in \
  skills/upstream-existing \
  codex-skills/codex-new \
  other-skills/alpha/staged-existing \
  other-skills/alpha/staged-new; do
  printf '%s\n' "fixture $path" > "$FIXTURE/$path/SKILL.md"
done
# Ten text characters, but twelve UTF-8 bytes: preserve Python's character-count
# and ties-to-even rounding semantics (round(10 / 4) == 2).
printf '%s\n' '12345678—' > "$FIXTURE/skills/upstream-existing/SKILL.md"
printf '%s\n' 'fixture plugin' > "$HOME_ROOT/plugin-target/SKILL.md"
ln -s "$HOME_ROOT/plugin-target/SKILL.md" \
  "$HOME_ROOT/.claude/plugins/cache/example/plugin-existing/1.0.0/SKILL.md"
cat > "$FIXTURE/other-skills/alpha/.source.json" <<'JSON'
{"repo":"https://github.com/example/alpha-skills.git","commit":"abc","syncedAt":"2026-07-28T00:00:00Z"}
JSON
cat > "$HOME_ROOT/.claude/plugins/known_marketplaces.json" <<'JSON'
{"example":{"source":{"repo":"https://github.com/example/plugin-existing.git"}}}
JSON
cat > "$HOME_ROOT/.claude/settings.json" <<'JSON'
{"enabledPlugins":{"plugin-existing@example":true}}
JSON
mkdir -p "$HOME_ROOT/.codex"
cat > "$HOME_ROOT/.codex/config.toml" <<'TOML'
[plugins."plugin-existing"]

enabled = true
TOML
cat > "$FIXTURE/agent-tooling/skills-matrix.md" <<'MARKDOWN'
# Skills matrix

Hand-edit Claude/Codex selections; regeneration preserves them.

## Counts

| Availability | Claude | Codex |
|---|---|---|
| Total | 999 | 999 |

| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `plugin-existing` | old/plugin-source | plugin | Y | Y | ~1 |
| `staged-existing` | old/staged-source | skill | Y | Y | ~1 |
| `stale-selected` | old/stale-source | skill | N | Y | ~1 |
| `upstream-existing` | old/upstream-source | skill | Y | N | ~1 |

<!-- total=999 -->

## Enable-state

stale

## Repos

stale
MARKDOWN

HOME="$HOME_ROOT" /bin/bash "$FIXTURE/agent-tooling/generate-skills-matrix.sh" \
  > "$FIXTURE/generated.md"

# Existing selections remain verbatim even when attribution is refreshed.
rg '^\| `plugin-existing` \| example/plugin-existing \| plugin \| Y \| Y \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `staged-existing` \| example/alpha-skills \| skill \| Y \| Y \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `upstream-existing` \| steipete/agent-scripts \| skill \| Y \| N \| ~2 \|$' \
  "$FIXTURE/generated.md" >/dev/null

# Newly discovered rows are appended unselected; stale rows remain actionable.
rg '^\| `codex-new` \| marcuslannister/agent-scripts \| skill \| N \| N \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `staged-new` \| example/alpha-skills \| skill \| N \| N \|' \
  "$FIXTURE/generated.md" >/dev/null
rg '^\| `stale-selected` \| old/stale-source \| skill \| N \| Y \|' \
  "$FIXTURE/generated.md" >/dev/null

# Derived sections are recomputed from preserved selections.
rg -F '| Total | 3 | 3 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Shared | 2 | 2 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Agent-only | 1 | 1 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Enabled | 1 | 1 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Disabled | 0 | 0 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| Always-on | 2 | 2 |' "$FIXTURE/generated.md" >/dev/null
rg -F '| `example/alpha-skills` | https://github.com/example/alpha-skills |' \
  "$FIXTURE/generated.md" >/dev/null

# Cleanup must preserve a generator failure so update-all cannot install empty output.
mkdir -p "$TMP_ROOT/failing-bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 17' > "$TMP_ROOT/failing-bin/awk"
chmod +x "$TMP_ROOT/failing-bin/awk"
if PATH="$TMP_ROOT/failing-bin:$PATH" HOME="$HOME_ROOT" \
  /bin/bash "$FIXTURE/agent-tooling/generate-skills-matrix.sh" \
  > "$TMP_ROOT/failure.out" 2> "$TMP_ROOT/failure.err"; then
  echo "FAIL: matrix generator masked a subprocess failure" >&2
  exit 1
fi

echo "generate-skills-matrix selection-preservation tests passed"
