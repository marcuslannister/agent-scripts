#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/skill-authors.json"
GEN="$REPO_ROOT/scripts/generate-skill-index.sh"

# Registry shape (per issue #26: explicit per-skill registry, all 116 stated).
jq -e '.skills | length == 116' "$REGISTRY" >/dev/null
jq -e '.skills | has("onecli-gateway") | not' "$REGISTRY" >/dev/null
jq -e '.skills | has("onecli-run") | not' "$REGISTRY" >/dev/null
jq -e '.authorOrder == ["marcus","steipete","matt","anthropic","khazix"]' "$REGISTRY" >/dev/null
jq -e '[.skills[]] | unique == ["anthropic","khazix","marcus","matt","steipete"]' "$REGISTRY" >/dev/null

# Evidence-based / wholesale attributions (spot check).
jq -e '.skills["peekaboo"] == "steipete"' "$REGISTRY" >/dev/null
jq -e '.skills["review-claudemd"] == "marcus"' "$REGISTRY" >/dev/null
jq -e '.skills["grilling"] == "matt"' "$REGISTRY" >/dev/null
jq -e '.skills["frontend-design"] == "steipete"' "$REGISTRY" >/dev/null
jq -e '.skills["neat-freak"] == "khazix"' "$REGISTRY" >/dev/null

# Every on-disk skill is attributed and the committed INDEX.md is fresh.
"$GEN" --check >/dev/null

# The generator is idempotent: a rewrite reproduces the committed index byte-for-byte.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$REPO_ROOT/INDEX.md" "$TMP/before"
"$GEN" >/dev/null
diff -u "$TMP/before" "$REPO_ROOT/INDEX.md"

# A skills/ dir with no registry entry must fail the generator.
FIX="$TMP/repo"
mkdir -p "$FIX/scripts" "$FIX/skills/orphan-skill"
cp "$GEN" "$FIX/scripts/generate-skill-index.sh"
cp "$REGISTRY" "$FIX/skill-authors.json"
cp "$REPO_ROOT/INDEX.md" "$FIX/INDEX.md"
printf '%s\n' '---' 'name: orphan-skill' 'description: "x"' '---' body > "$FIX/skills/orphan-skill/SKILL.md"
if bash "$FIX/scripts/generate-skill-index.sh" --check 2>/dev/null; then
  echo "FAIL: unattributed skill did not fail the generator" >&2
  exit 1
fi

echo "skill-index tests passed"
