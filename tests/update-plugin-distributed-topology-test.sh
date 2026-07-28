#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

jq -e '
  .sources[] | select(.id == "openai-codex") |
  .classification == "plugin-claude-only" and
  .defaultDestinations == ["claude"] and
  has("overrides") == false
' "$REPO_ROOT/agent-tooling/skill-topology.json" >/dev/null
jq -e '
  .[] | select(.sourceId == "openai-codex") |
  .classification == "plugin-claude-only" and
  .supportedDestinations == ["claude"] and
  .command == "adapters/plugin-both.sh" and
  .plugin == {
    name: "codex",
    repo: "openai/codex-plugin-cc",
    marketplaces: {claude: "openai-codex"},
    skills: ["codex"]
  }
' "$REPO_ROOT/agent-tooling/distribution-topology/registry.json" >/dev/null

jq -e '
  ([.sources[] | select(.id == "waza" or .id == "claude-mem") | {
    id, classification, defaultDestinations, overrides
  }] | length) == 2 and
  all(.sources[] | select(.id == "waza" or .id == "claude-mem");
    .classification == "dual-plugin" and
    .defaultDestinations == ["claude","codex"] and
    (has("overrides") | not))
' "$REPO_ROOT/agent-tooling/skill-topology.json" >/dev/null
jq -e '
  ([.[] | select(.sourceId == "waza" or .sourceId == "claude-mem")] | length) == 2 and
  all(.[] | select(.sourceId == "waza" or .sourceId == "claude-mem");
    .classification == "dual-plugin" and
    (.plugin.skills | type == "array" and length > 0) and
    (.plugin.skills | length == (unique | length))) and
  (.[] | select(.sourceId == "waza") | .plugin.skills == ["waza"]) and
  (.[] | select(.sourceId == "claude-mem") | .plugin.skills == ["claude-mem"])
' "$REPO_ROOT/agent-tooling/distribution-topology/registry.json" >/dev/null

RETIRED_CLASSIFICATION_FIXTURE="$TMP_ROOT/retired-plugin-both"
mkdir -p "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling" "$RETIRED_CLASSIFICATION_FIXTURE/home" "$RETIRED_CLASSIFICATION_FIXTURE/runtime"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling/"
jq '{version, sources: [.sources[] | select(.id == "waza") | .classification = "plugin-both"]}'   "$REPO_ROOT/agent-tooling/skill-topology.json" > "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling/skill-topology.json"
jq '[.[] | select(.sourceId == "waza") | .classification = "plugin-both"]'   "$REPO_ROOT/agent-tooling/distribution-topology/registry.json"   > "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling/distribution-topology/registry.json"
set +e
HOME="$RETIRED_CLASSIFICATION_FIXTURE/home" TMPDIR="$RETIRED_CLASSIFICATION_FIXTURE/runtime" PATH="/usr/bin:/bin:/usr/sbin:/sbin"   "$RETIRED_CLASSIFICATION_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json   > "$RETIRED_CLASSIFICATION_FIXTURE/result.json"
retired_exit=$?
set -e
test "$retired_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("unknown classification: plugin-both"))
' "$RETIRED_CLASSIFICATION_FIXTURE/result.json" >/dev/null

MISSING_SKILLS_FIXTURE="$TMP_ROOT/missing-plugin-skills"
mkdir -p "$MISSING_SKILLS_FIXTURE/agent-tooling" "$MISSING_SKILLS_FIXTURE/home" "$MISSING_SKILLS_FIXTURE/runtime"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$MISSING_SKILLS_FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$MISSING_SKILLS_FIXTURE/agent-tooling/"
jq '{version, sources: [.sources[] | select(.id == "waza")]}'   "$REPO_ROOT/agent-tooling/skill-topology.json" > "$MISSING_SKILLS_FIXTURE/agent-tooling/skill-topology.json"
jq '[.[] | select(.sourceId == "waza") | .plugin |= del(.skills)]'   "$REPO_ROOT/agent-tooling/distribution-topology/registry.json"   > "$MISSING_SKILLS_FIXTURE/agent-tooling/distribution-topology/registry.json"
set +e
HOME="$MISSING_SKILLS_FIXTURE/home" TMPDIR="$MISSING_SKILLS_FIXTURE/runtime" PATH="/usr/bin:/bin:/usr/sbin:/sbin"   "$MISSING_SKILLS_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json   > "$MISSING_SKILLS_FIXTURE/result.json"
missing_skills_exit=$?
set -e
test "$missing_skills_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("plugin is missing required field: skills")
    or contains("plugin skills must be a non-empty array"))
' "$MISSING_SKILLS_FIXTURE/result.json" >/dev/null

FIXTURE="$TMP_ROOT/waza"
BIN="$FIXTURE/bin"
mkdir -p "$FIXTURE/agent-tooling" "$FIXTURE/home/.codex" "$FIXTURE/home/.claude/skills" "$FIXTURE/runtime" "$BIN" \
  "$FIXTURE/home/claude-marketplace/.claude-plugin" \
  "$FIXTURE/home/codex-marketplace/.agents/plugins" \
  "$FIXTURE/home/codex-marketplace/plugins/waza/.codex-plugin" \
  "$FIXTURE/home/plugin-roots/claude/waza/skills/think" \
  "$FIXTURE/home/plugin-roots/codex/waza/skills/think" \
  "$FIXTURE/remote-marketplace/.claude-plugin" \
  "$FIXTURE/remote-marketplace/.agents/plugins" \
  "$FIXTURE/remote-marketplace/plugins/waza/.codex-plugin" \
  "$FIXTURE/remote-marketplace/skills/think"
printf 'claude-skills\n' > "$FIXTURE/home/.claude/skills/.agent-scripts-root"
printf '# Waza think\n' > "$FIXTURE/home/plugin-roots/claude/waza/skills/think/SKILL.md"
printf '# Waza think\n' > "$FIXTURE/home/plugin-roots/codex/waza/skills/think/SKILL.md"
printf '# Waza think\n' > "$FIXTURE/remote-marketplace/skills/think/SKILL.md"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"

cat > "$FIXTURE/agent-tooling/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "waza",
      "classification": "dual-plugin",
      "defaultDestinations": ["claude", "codex"]
    }
  ]
}
JSON

cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "waza",
    "classification": "dual-plugin",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/plugin-both.sh",
    "stateInspection": "adapter",
    "plugin": {
      "name": "waza",
      "repo": "tw93/Waza",
      "marketplaces": {"claude": "waza", "codex": "waza"},
      "skills": ["waza"]
    }
  }
]
JSON

printf '[]\n' > "$FIXTURE/home/claude-plugins.json"
printf '[]\n' > "$FIXTURE/home/claude-marketplaces.json"
printf '{"installed":[]}\n' > "$FIXTURE/home/codex-plugins.json"
printf '{"marketplaces":[]}\n' > "$FIXTURE/home/codex-marketplaces.json"
cat > "$FIXTURE/home/.codex/config.toml" <<'TOML'
[plugins."waza@waza"]
enabled = true
TOML
cat > "$FIXTURE/home/claude-marketplace/.claude-plugin/marketplace.json" <<'JSON'
{"name":"waza","plugins":[{"name":"waza","version":"1.0.0","source":"./"}]}
JSON
cat > "$FIXTURE/home/codex-marketplace/.agents/plugins/marketplace.json" <<'JSON'
{"name":"waza","plugins":[{"name":"waza","source":{"source":"local","path":"./plugins/waza"}}]}
JSON
cat > "$FIXTURE/home/codex-marketplace/plugins/waza/.codex-plugin/plugin.json" <<'JSON'
{"name":"waza","version":"1.0.0"}
JSON
cp "$FIXTURE/home/claude-marketplace/.claude-plugin/marketplace.json" \
  "$FIXTURE/remote-marketplace/.claude-plugin/marketplace.json"
cp "$FIXTURE/home/codex-marketplace/.agents/plugins/marketplace.json" \
  "$FIXTURE/remote-marketplace/.agents/plugins/marketplace.json"
cp "$FIXTURE/home/codex-marketplace/plugins/waza/.codex-plugin/plugin.json" \
  "$FIXTURE/remote-marketplace/plugins/waza/.codex-plugin/plugin.json"

cat > "$BIN/claude" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    jq --arg path "$HOME/plugin-roots/claude/waza" '
      map(if .id == "waza@waza" then .installPath = $path else . end)
    ' "$HOME/claude-plugins.json"
    ;;
  'plugin marketplace list --json')
    if [ "${FAKE_CLAUDE_FRESHNESS_FAIL:-0}" = 1 ]; then
      printf 'fixture Claude freshness failure\n' >&2
      exit 1
    fi
    jq --arg root "$HOME/claude-marketplace" 'map(. + {installLocation:$root})' \
      "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace add tw93/Waza')
    printf '[{"name":"waza"}]\n' > "$HOME/claude-marketplaces.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin marketplace update waza')
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    if [ "${FAKE_CLAUDE_MARKETPLACE_FAIL:-0}" = 1 ]; then
      printf 'fixture Claude marketplace failure\n' >&2
      exit 1
    fi
    ;;
  'plugin install waza@waza')
    mkdir -p "$HOME/plugin-roots/claude/waza/skills/think"
    [ -f "$HOME/plugin-roots/claude/waza/skills/think/SKILL.md" ] || \
      printf '# Waza think\n' > "$HOME/plugin-roots/claude/waza/skills/think/SKILL.md"
    jq -n --arg path "$HOME/plugin-roots/claude/waza" \
      '[{id:"waza@waza",version:"1.0.0",enabled:true,installPath:$path}]' \
      > "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin enable waza@waza')
    jq 'map(if .id == "waza@waza" then .enabled = true else . end)' \
      "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
    mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin update waza@waza')
    if [ -n "${FAKE_PLUGIN_UPDATE_VERSION:-}" ]; then
      jq --arg version "$FAKE_PLUGIN_UPDATE_VERSION" \
        'map(if .id == "waza@waza" then .version = $version else . end)' \
        "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
      mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    fi
    if [ -n "${FAKE_DROP_SKILL_ON_UPDATE:-}" ] && \
      [ -d "$HOME/plugin-roots/claude/waza/skills/$FAKE_DROP_SKILL_ON_UPDATE" ]; then
      mv "$HOME/plugin-roots/claude/waza/skills/$FAKE_DROP_SKILL_ON_UPDATE" \
        "$HOME/dropped-claude-$FAKE_DROP_SKILL_ON_UPDATE"
    fi
    if [ "${FAKE_CLAUDE_ENABLE_ON_UPDATE:-0}" = 1 ]; then
      jq 'map(if .id == "waza@waza" then .enabled = true else . end)' \
        "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
      mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    fi
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  'plugin disable waza@waza')
    jq 'map(if .id == "waza@waza" then .enabled = false else . end)' \
      "$HOME/claude-plugins.json" > "$HOME/claude-plugins.tmp"
    mv "$HOME/claude-plugins.tmp" "$HOME/claude-plugins.json"
    printf '%s\n' "$*" >> "$HOME/claude-mutations.log"
    ;;
  *)
    printf 'unexpected claude call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    enabled="$(awk '
      $0 == "[plugins.\"waza@waza\"]" { in_plugin = 1; next }
      in_plugin && /^\[/ { exit }
      in_plugin && /^enabled[[:space:]]*=/ { print $3; exit }
    ' "$HOME/.codex/config.toml")"
    jq --argjson enabled "${enabled:-true}" --arg path "$HOME/plugin-roots/codex/waza" '
      .installed |= map(
        if .pluginId == "waza@waza" then
          .enabled = $enabled
          | .source = ((.source // {}) + {source:"local", path:$path})
        else . end
      )
    ' "$HOME/codex-plugins.json"
    ;;
  'plugin marketplace list --json')
    if [ "${FAKE_CODEX_FRESHNESS_FAIL:-0}" = 1 ]; then
      printf 'fixture Codex freshness failure\n' >&2
      exit 1
    fi
    jq --arg root "$HOME/codex-marketplace" '.marketplaces |= map(. + {root:$root})' \
      "$HOME/codex-marketplaces.json"
    ;;
  'plugin marketplace add tw93/Waza')
    printf '{"marketplaces":[{"name":"waza"}]}\n' > "$HOME/codex-marketplaces.json"
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    ;;
  'plugin marketplace upgrade waza')
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    if [ "${FAKE_CODEX_MARKETPLACE_FAIL:-0}" = 1 ]; then
      printf 'fixture Codex marketplace failure\n' >&2
      exit 1
    fi
    ;;
  'plugin add waza@waza')
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    if [ "${FAKE_CODEX_INSTALL_FAIL:-0}" = 1 ]; then
      printf 'fixture Codex install failure\n' >&2
      exit 1
    fi
    mkdir -p "$HOME/plugin-roots/codex/waza/skills/think"
    [ -f "$HOME/plugin-roots/codex/waza/skills/think/SKILL.md" ] || \
      printf '# Waza think\n' > "$HOME/plugin-roots/codex/waza/skills/think/SKILL.md"
    perl -pi -e 's/^enabled = false$/enabled = true/' "$HOME/.codex/config.toml"
    if jq -e '.installed[]? | select(.pluginId == "waza@waza")' "$HOME/codex-plugins.json" >/dev/null; then
      jq --arg version "${FAKE_PLUGIN_UPDATE_VERSION:-1.0.0}" --arg path "$HOME/plugin-roots/codex/waza" '
        .installed |= map(if .pluginId == "waza@waza" then
          .version = $version | .enabled = true | .source = {source:"local",path:$path}
        else . end)
      ' "$HOME/codex-plugins.json" > "$HOME/codex-plugins.tmp"
      mv "$HOME/codex-plugins.tmp" "$HOME/codex-plugins.json"
    else
      jq -n --arg version "${FAKE_PLUGIN_UPDATE_VERSION:-1.0.0}" --arg path "$HOME/plugin-roots/codex/waza" '
        {installed:[{pluginId:"waza@waza",marketplaceName:"waza",version:$version,installed:true,enabled:true,source:{source:"local",path:$path}}]}
      ' > "$HOME/codex-plugins.json"
    fi
    if [ -n "${FAKE_DROP_SKILL_ON_UPDATE:-}" ] && \
      [ -d "$HOME/plugin-roots/codex/waza/skills/$FAKE_DROP_SKILL_ON_UPDATE" ]; then
      mv "$HOME/plugin-roots/codex/waza/skills/$FAKE_DROP_SKILL_ON_UPDATE" \
        "$HOME/dropped-codex-$FAKE_DROP_SKILL_ON_UPDATE"
    fi
    ;;
  'plugin remove waza@waza')
    printf '{"installed":[]}\n' > "$HOME/codex-plugins.json"
    printf '%s\n' "$*" >> "$HOME/codex-mutations.log"
    ;;
  *)
    printf 'unexpected codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
test "$#" -eq 6
test "$1" = clone
test "$2" = --depth
test "$3" = 1
test "$4" = --quiet
test "$5" = https://github.com/tw93/Waza.git
if [ "${FAKE_GIT_CLONE_FAIL:-0}" = 1 ]; then
  printf 'fixture remote discovery failure\n' >&2
  exit 1
fi
destination="$6"
mkdir -p "$destination"
cp -R "${HOME%/home}/remote-marketplace/." "$destination"
printf '%s\n' "$destination" >> "${FAKE_GIT_LOG:-/dev/null}"
BASH
chmod +x "$BIN/claude" "$BIN/codex" "$BIN/git"

OPENAI_FIXTURE="$TMP_ROOT/openai-codex"
cp -R "$FIXTURE" "$OPENAI_FIXTURE"
jq '{version, sources: [.sources[] | select(.id == "openai-codex")]}' \
  "$REPO_ROOT/agent-tooling/skill-topology.json" > "$OPENAI_FIXTURE/agent-tooling/skill-topology.json"
jq '[.[] | select(.sourceId == "openai-codex")]' \
  "$REPO_ROOT/agent-tooling/distribution-topology/registry.json" \
  > "$OPENAI_FIXTURE/agent-tooling/distribution-topology/registry.json"
cat > "$OPENAI_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json" <<'JSON'
{"name":"openai-codex","plugins":[{"name":"codex","version":"1.0.6","source":"./plugins/codex"}]}
JSON
mkdir -p "$OPENAI_FIXTURE/home/plugin-roots/claude/codex/skills/codex-cli-runtime"
printf '# Codex runtime\n' > "$OPENAI_FIXTURE/home/plugin-roots/claude/codex/skills/codex-cli-runtime/SKILL.md"
jq -n --arg path "$OPENAI_FIXTURE/home/plugin-roots/claude/codex" \
  '[{id:"codex@openai-codex",version:"1.0.6",enabled:true,installPath:$path}]' \
  > "$OPENAI_FIXTURE/home/claude-plugins.json"
perl -pi -e 's!tw93/Waza!openai/codex-plugin-cc!g' "$OPENAI_FIXTURE/bin/git"
HOME="$OPENAI_FIXTURE/home" TMPDIR="$OPENAI_FIXTURE/runtime" \
PATH="$OPENAI_FIXTURE/bin:$PATH" \
  "$OPENAI_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$OPENAI_FIXTURE/result.json"
if ! jq -e '
  .status == "clean" and
  ([.plan[] | {sourceId,skill,destinations}] == [
    {sourceId:"openai-codex",skill:"codex",destinations:["claude"]}
  ]) and
  .decisions == [] and .errors == []
' "$OPENAI_FIXTURE/result.json" >/dev/null; then
  cat "$OPENAI_FIXTURE/result.json" >&2
  exit 1
fi

COMMAND="$FIXTURE/agent-tooling/update-skill-topology.sh"
MISSING_METADATA_FIXTURE="$TMP_ROOT/missing-plugin-metadata"
cp -R "$FIXTURE" "$MISSING_METADATA_FIXTURE"
jq '.[0] |= del(.plugin)' \
  "$MISSING_METADATA_FIXTURE/agent-tooling/distribution-topology/registry.json" > "$MISSING_METADATA_FIXTURE/registry.tmp"
mv "$MISSING_METADATA_FIXTURE/registry.tmp" "$MISSING_METADATA_FIXTURE/agent-tooling/distribution-topology/registry.json"
set +e
HOME="$MISSING_METADATA_FIXTURE/home" TMPDIR="$MISSING_METADATA_FIXTURE/runtime" \
PATH="$MISSING_METADATA_FIXTURE/bin:$PATH" \
  "$MISSING_METADATA_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json > "$MISSING_METADATA_FIXTURE/result.json"
missing_metadata_exit=$?
set -e
test "$missing_metadata_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("requires plugin metadata for a plugin source"))
' "$MISSING_METADATA_FIXTURE/result.json" >/dev/null
jq -e '. == []' "$MISSING_METADATA_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed == []' "$MISSING_METADATA_FIXTURE/home/codex-plugins.json" >/dev/null

NULL_METADATA_FIXTURE="$TMP_ROOT/null-plugin-metadata"
cp -R "$FIXTURE" "$NULL_METADATA_FIXTURE"
jq '.[0].classification = "plugin-claude-only" | .[0].plugin = null' \
  "$NULL_METADATA_FIXTURE/agent-tooling/distribution-topology/registry.json" > "$NULL_METADATA_FIXTURE/registry.tmp"
mv "$NULL_METADATA_FIXTURE/registry.tmp" "$NULL_METADATA_FIXTURE/agent-tooling/distribution-topology/registry.json"
jq '.sources[0].classification = "plugin-claude-only"' \
  "$NULL_METADATA_FIXTURE/agent-tooling/skill-topology.json" > "$NULL_METADATA_FIXTURE/manifest.tmp"
mv "$NULL_METADATA_FIXTURE/manifest.tmp" "$NULL_METADATA_FIXTURE/agent-tooling/skill-topology.json"
set +e
HOME="$NULL_METADATA_FIXTURE/home" TMPDIR="$NULL_METADATA_FIXTURE/runtime" \
PATH="$NULL_METADATA_FIXTURE/bin:$PATH" \
  "$NULL_METADATA_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json > "$NULL_METADATA_FIXTURE/result.json"
null_metadata_exit=$?
set -e
test "$null_metadata_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("requires plugin metadata for a plugin source"))
' "$NULL_METADATA_FIXTURE/result.json" >/dev/null
jq -e '. == []' "$NULL_METADATA_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed == []' "$NULL_METADATA_FIXTURE/home/codex-plugins.json" >/dev/null

UNSUPPORTED_MARKETPLACE_FIXTURE="$TMP_ROOT/unsupported-plugin-marketplace"
cp -R "$FIXTURE" "$UNSUPPORTED_MARKETPLACE_FIXTURE"
jq '.[0].classification = "plugin-claude-only"' \
  "$UNSUPPORTED_MARKETPLACE_FIXTURE/agent-tooling/distribution-topology/registry.json" > "$UNSUPPORTED_MARKETPLACE_FIXTURE/registry.tmp"
mv "$UNSUPPORTED_MARKETPLACE_FIXTURE/registry.tmp" "$UNSUPPORTED_MARKETPLACE_FIXTURE/agent-tooling/distribution-topology/registry.json"
jq '.sources[0].classification = "plugin-claude-only"' \
  "$UNSUPPORTED_MARKETPLACE_FIXTURE/agent-tooling/skill-topology.json" > "$UNSUPPORTED_MARKETPLACE_FIXTURE/manifest.tmp"
mv "$UNSUPPORTED_MARKETPLACE_FIXTURE/manifest.tmp" "$UNSUPPORTED_MARKETPLACE_FIXTURE/agent-tooling/skill-topology.json"
set +e
HOME="$UNSUPPORTED_MARKETPLACE_FIXTURE/home" TMPDIR="$UNSUPPORTED_MARKETPLACE_FIXTURE/runtime" \
PATH="$UNSUPPORTED_MARKETPLACE_FIXTURE/bin:$PATH" \
  "$UNSUPPORTED_MARKETPLACE_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json > "$UNSUPPORTED_MARKETPLACE_FIXTURE/result.json"
unsupported_marketplace_exit=$?
set -e
test "$unsupported_marketplace_exit" -eq 2
jq -e '
  .status == "invalid" and
  (.errors[0] | contains("marketplaces contains unsupported destination: codex"))
' "$UNSUPPORTED_MARKETPLACE_FIXTURE/result.json" >/dev/null
jq -e '. == []' "$UNSUPPORTED_MARKETPLACE_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed == []' "$UNSUPPORTED_MARKETPLACE_FIXTURE/home/codex-plugins.json" >/dev/null

MISSING_PLUGIN_FIXTURE="$TMP_ROOT/missing-plugin-check"
cp -R "$FIXTURE" "$MISSING_PLUGIN_FIXTURE"
cp -R "$MISSING_PLUGIN_FIXTURE/home" "$MISSING_PLUGIN_FIXTURE/home-before-check"
set +e
HOME="$MISSING_PLUGIN_FIXTURE/home" TMPDIR="$MISSING_PLUGIN_FIXTURE/runtime" \
PATH="$MISSING_PLUGIN_FIXTURE/bin:$PATH" \
  "$MISSING_PLUGIN_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$MISSING_PLUGIN_FIXTURE/result.json"
missing_plugin_exit=$?
set -e
test "$missing_plugin_exit" -eq 1
jq -e '
  .status == "drift" and
  ([.drift[] | {sourceId, skill, destination, reason}] == [
    {"sourceId":"waza","skill":"waza","destination":"claude","reason":"missing"},
    {"sourceId":"waza","skill":"waza","destination":"codex","reason":"missing"}
  ]) and
  ([.changes[] | {action, sourceId, skill, destination}] == [
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"claude"},
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"codex"}
  ]) and
  .errors == []
' "$MISSING_PLUGIN_FIXTURE/result.json" >/dev/null
diff -r "$MISSING_PLUGIN_FIXTURE/home-before-check" "$MISSING_PLUGIN_FIXTURE/home" >/dev/null

# End-to-end dual-plugin migration: preview, partial native success, gated copy
# retention, verified cleanup, unrelated-copy preservation, and idempotence.
MIGRATION_FIXTURE="$TMP_ROOT/dual-plugin-migration"
cp -R "$FIXTURE" "$MIGRATION_FIXTURE"
mkdir -p "$MIGRATION_FIXTURE/home/.claude/skills/waza" \
  "$MIGRATION_FIXTURE/home/.claude/skills/not-native" \
  "$MIGRATION_FIXTURE/home/.agents/skills/waza" \
  "$MIGRATION_FIXTURE/home/.agents/skills/not-native"
printf '# tracked Waza copy\n' > "$MIGRATION_FIXTURE/home/.claude/skills/waza/SKILL.md"
printf '%s\n%s\n%s\n' \
  "$MIGRATION_FIXTURE/remote-marketplace/skills" repo-skills stale-hash \
  > "$MIGRATION_FIXTURE/home/.claude/skills/waza/.agent-scripts-copy"
printf '# unrelated tracked copy\n' > "$MIGRATION_FIXTURE/home/.claude/skills/not-native/SKILL.md"
printf '# hand edit\n' >> "$MIGRATION_FIXTURE/home/.claude/skills/waza/SKILL.md"
printf '# managed Waza copy\n' > "$MIGRATION_FIXTURE/home/.agents/skills/waza/SKILL.md"
printf '%s\n%s\n%s\n' \
  "$MIGRATION_FIXTURE/remote-marketplace/skills" repo-skills stale-hash \
  > "$MIGRATION_FIXTURE/home/.agents/skills/waza/.agent-scripts-copy"
printf '# unrelated untracked copy\n' \
  > "$MIGRATION_FIXTURE/home/.agents/skills/not-native/SKILL.md"

cp -R "$MIGRATION_FIXTURE/home" "$MIGRATION_FIXTURE/home-before-check"
cp "$MIGRATION_FIXTURE/home/.claude/skills/waza/SKILL.md" "$MIGRATION_FIXTURE/waza-before-check"
set +e
HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" \
PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$MIGRATION_FIXTURE/check.json"
migration_check_exit=$?
set -e
test "$migration_check_exit" -eq 1
if ! jq -e '
  .status == "drift" and
  (.migrations == [{
    sourceId:"waza",
    skill:"waza",
    gate:"pending",
    native:[
      {destination:"claude",status:"missing"},
      {destination:"codex",status:"missing"}
    ],
    copies:[
      {destination:"claude",state:"present",action:"retain",afterGate:"remove"},
      {destination:"codex",state:"present",action:"retain",afterGate:"remove"}
    ]
  }])
' "$MIGRATION_FIXTURE/check.json" >/dev/null; then
  cat "$MIGRATION_FIXTURE/check.json" >&2
  exit 1
fi
jq -e '
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery == {required:false,actions:[]} and
  .state == "drift" and .idempotent == false and
  any(.events[]; .kind == "native-reconciliation" and .phase == "plan" and
    .destination == "claude" and .action == "install" and .status == "planned") and
  any(.events[]; .kind == "runtime-verification" and .destination == "codex" and
    .status == "blocked" and .reason == "missing") and
  ([.events[] | select(.kind == "copy-retained") | .destination] == ["claude","codex"])
' "$MIGRATION_FIXTURE/check.json" >/dev/null
diff -r "$MIGRATION_FIXTURE/home-before-check" "$MIGRATION_FIXTURE/home" >/dev/null
cmp -s "$MIGRATION_FIXTURE/waza-before-check" "$MIGRATION_FIXTURE/home/.claude/skills/waza/SKILL.md"

set +e
HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" PATH="$MIGRATION_FIXTURE/bin:$PATH"   "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --check   > "$MIGRATION_FIXTURE/check.out" 2> "$MIGRATION_FIXTURE/check.err"
migration_human_check_exit=$?
set -e
test "$migration_human_check_exit" -eq 1
test ! -s "$MIGRATION_FIXTURE/check.err"
rg -q '^waza/waza +claude +native-plan:install +planned$' "$MIGRATION_FIXTURE/check.out"
rg -q '^waza/waza +codex +runtime-verification:missing +blocked$' "$MIGRATION_FIXTURE/check.out"
rg -q '^waza/waza +claude +copy-retained:gate-pending +retained$' "$MIGRATION_FIXTURE/check.out"
! rg -q '^waza/waza +(claude|codex|claude,codex) +(installed:|gate:|copy-retained-until-gate|planned-copy-removal)' \
  "$MIGRATION_FIXTURE/check.out"

set +e
FAKE_CODEX_INSTALL_FAIL=1 \
HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" \
PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MIGRATION_FIXTURE/partial.json"
migration_partial_exit=$?
set -e
test "$migration_partial_exit" -eq 1
jq -e '
  .status == "failed" and .state == "failed" and .idempotent == false and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  (.migrations[0].gate == "blocked") and
  ([.migrations[0].native[] | .status] == ["verified","missing"]) and
  any(.events[]; .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "claude" and .action == "install" and .status == "applied") and
  any(.events[]; .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "codex" and .action == "install" and .status == "failed") and
  any(.events[]; .kind == "runtime-verification" and .destination == "codex" and
    .status == "blocked" and .reason == "missing") and
  ([.events[] | select(.kind == "copy-retained") | .destination] == ["claude","codex"]) and
  any(.events[]; .kind == "blocking-failure" and
    (.message | contains("Codex plugin install failed"))) and
  all(.migrations[0].copies[]; .state == "present" and .action == "retain") and
  any(.errors[]; contains("Codex plugin install failed")) and
  ([.changes[] | select(.action == "copy-removed")] == [])
' "$MIGRATION_FIXTURE/partial.json" >/dev/null
test -f "$MIGRATION_FIXTURE/home/.claude/skills/waza/SKILL.md"
test -f "$MIGRATION_FIXTURE/home/.agents/skills/waza/SKILL.md"

set +e
FAKE_CODEX_INSTALL_FAIL=1 HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" PATH="$MIGRATION_FIXTURE/bin:$PATH"   "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh"   > "$MIGRATION_FIXTURE/partial.out" 2> "$MIGRATION_FIXTURE/partial.err"
migration_partial_human_exit=$?
set -e
test "$migration_partial_human_exit" -eq 1
rg -q '^waza/waza +codex +native-apply:install +failed$' "$MIGRATION_FIXTURE/partial.out"
rg -q '^waza/waza +codex +runtime-verification:missing +blocked$' "$MIGRATION_FIXTURE/partial.out"
rg -q '^waza/waza +codex +copy-retained:gate-blocked +retained$' "$MIGRATION_FIXTURE/partial.out"
rg -Fq 'Recovery: upstream repair, native rollback, or explicit manifest decision.' \
  "$MIGRATION_FIXTURE/partial.err"

HOME="$MIGRATION_FIXTURE/home" PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  codex plugin add waza@waza
cp -R "$MIGRATION_FIXTURE/home" "$MIGRATION_FIXTURE/home-before-ready-check"
set +e
HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" \
PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$MIGRATION_FIXTURE/ready-check.json"
migration_ready_check_exit=$?
set -e
test "$migration_ready_check_exit" -eq 1
jq -e '
  .status == "drift" and .state == "drift" and .idempotent == false and
  .errors == [] and .recovery == {required:false,actions:[]} and
  (.migrations[0].gate == "verified") and
  all(.migrations[0].native[]; .status == "verified") and
  ([.events[] | select(.kind == "runtime-verification" and .status == "verified") |
    .destination] == ["claude","codex"]) and
  ([.events[] | select(.kind == "copy-removal" and .status == "planned") |
    .destination] == ["claude","codex"]) and
  all(.migrations[0].copies[]; .state == "present" and .action == "remove") and
  ([.changes[] | select(.action == "copy-removed") | .destination] == ["claude","codex"])
' "$MIGRATION_FIXTURE/ready-check.json" >/dev/null
diff -r "$MIGRATION_FIXTURE/home-before-ready-check" "$MIGRATION_FIXTURE/home" >/dev/null

HUMAN_REMOVAL_FIXTURE="$TMP_ROOT/dual-plugin-human-removal"
cp -R "$MIGRATION_FIXTURE" "$HUMAN_REMOVAL_FIXTURE"
HOME="$HUMAN_REMOVAL_FIXTURE/home" TMPDIR="$HUMAN_REMOVAL_FIXTURE/runtime" PATH="$HUMAN_REMOVAL_FIXTURE/bin:$PATH"   "$HUMAN_REMOVAL_FIXTURE/agent-tooling/update-skill-topology.sh"   > "$HUMAN_REMOVAL_FIXTURE/result.out" 2> "$HUMAN_REMOVAL_FIXTURE/result.err"
test ! -s "$HUMAN_REMOVAL_FIXTURE/result.err"
rg -q '^waza/waza +claude +copy-removal +removed$' "$HUMAN_REMOVAL_FIXTURE/result.out"
rg -q '^waza/waza +codex +copy-removal +removed$' "$HUMAN_REMOVAL_FIXTURE/result.out"
! rg -q '^waza/waza +(claude|codex|claude,codex) +(copy-removed|gate:|planned-copy-removal)' \
  "$HUMAN_REMOVAL_FIXTURE/result.out"

CLEANUP_FAILURE_FIXTURE="$TMP_ROOT/dual-plugin-cleanup-failure"
cp -R "$MIGRATION_FIXTURE" "$CLEANUP_FAILURE_FIXTURE"
cat > "$CLEANUP_FAILURE_FIXTURE/bin/rm" <<'BASH'
#!/usr/bin/env bash
for argument in "$@"; do
  case "$argument" in */skills/waza) exit 1 ;; esac
done
exec /bin/rm "$@"
BASH
chmod +x "$CLEANUP_FAILURE_FIXTURE/bin/rm"
set +e
HOME="$CLEANUP_FAILURE_FIXTURE/home" TMPDIR="$CLEANUP_FAILURE_FIXTURE/runtime" \
PATH="$CLEANUP_FAILURE_FIXTURE/bin:$PATH" \
  "$CLEANUP_FAILURE_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$CLEANUP_FAILURE_FIXTURE/result.json"
cleanup_failure_exit=$?
set -e
test "$cleanup_failure_exit" -eq 1
jq -e '
  .status == "failed" and .state == "failed" and .idempotent == false and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  (.migrations[0].gate == "verified") and
  all(.migrations[0].copies[]; .state == "present" and .action == "remove") and
  ([.events[] | select(.kind == "copy-removal" and .status == "blocked") |
    .destination] == ["claude","codex"]) and
  any(.events[]; .kind == "blocking-failure" and
    (.message | contains("duplicate copy cleanup failed"))) and
  any(.errors[]; contains("duplicate copy cleanup failed: waza/waza -> claude")) and
  any(.errors[]; contains("duplicate copy cleanup failed: waza/waza -> codex")) and
  ([.changes[] | select(.action == "copy-removed")] == [])
' "$CLEANUP_FAILURE_FIXTURE/result.json" >/dev/null
test -f "$CLEANUP_FAILURE_FIXTURE/home/.claude/skills/waza/SKILL.md"
test -f "$CLEANUP_FAILURE_FIXTURE/home/.agents/skills/waza/SKILL.md"
test ! -e "$CLEANUP_FAILURE_FIXTURE/home/.agents/skills/waza/.fallback-copy"

mv "$MIGRATION_FIXTURE/home/.agents/skills/waza/.agent-scripts-copy" \
  "$MIGRATION_FIXTURE/unmarked-waza-copy-marker"
HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" \
PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MIGRATION_FIXTURE/full.json"
jq -e '
  .status == "reconciled" and .state == "changed" and .idempotent == false and
  .errors == [] and .recovery == {required:false,actions:[]} and
  (.migrations[0].gate == "verified") and
  all(.migrations[0].native[]; .status == "verified") and
  ([.events[] | select(.kind == "copy-removal" and .status == "removed") |
    .destination] == ["claude","codex"]) and
  all(.migrations[0].copies[]; .state == "absent" and .action == "none") and
  ([.changes[] | select(.action == "copy-removed") | .destination] == ["claude","codex"])
' "$MIGRATION_FIXTURE/full.json" >/dev/null
test ! -e "$MIGRATION_FIXTURE/home/.claude/skills/waza"
test ! -e "$MIGRATION_FIXTURE/home/.agents/skills/waza"
test -f "$MIGRATION_FIXTURE/home/.claude/skills/not-native/SKILL.md"
test -f "$MIGRATION_FIXTURE/home/.agents/skills/not-native/SKILL.md"
test -f "$MIGRATION_FIXTURE/unmarked-waza-copy-marker"

HOME="$MIGRATION_FIXTURE/home" TMPDIR="$MIGRATION_FIXTURE/runtime" \
PATH="$MIGRATION_FIXTURE/bin:$PATH" \
  "$MIGRATION_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MIGRATION_FIXTURE/repeat.json"
jq -e '
  .status == "reconciled" and .state == "clean" and .idempotent == true and
  .errors == [] and .recovery == {required:false,actions:[]} and
  ([.changes[] | select(.action == "copy-removed")] == []) and
  ([.events[] | select(.kind == "copy-removal")] == []) and
  (.migrations[0].gate == "verified") and
  all(.migrations[0].copies[]; .state == "absent" and .action == "none")
' "$MIGRATION_FIXTURE/repeat.json" >/dev/null

# One multi-skill plugin bundle mutates once per CLI. A skill withdrawn during
# update blocks only its own copy cleanup; another verified skill still migrates.
seed_multi_skill_duplicates() {
  local root="$1" skill
  mkdir -p "$root/home/.claude/skills/think" "$root/home/.claude/skills/write" \
    "$root/home/.agents/skills/think" "$root/home/.agents/skills/write"
  for skill in think write; do
    printf '# duplicate\n' > "$root/home/.claude/skills/$skill/SKILL.md"
    printf '# duplicate\n' > "$root/home/.agents/skills/$skill/SKILL.md"
    printf '%s\n%s\n%s\n' "$root/remote-marketplace/skills" repo-skills stale-hash \
      > "$root/home/.claude/skills/$skill/.agent-scripts-copy"
    printf '%s\n%s\n%s\n' "$root/remote-marketplace/skills" repo-skills stale-hash \
      > "$root/home/.agents/skills/$skill/.agent-scripts-copy"
  done
}

MULTI_SKILL_FIXTURE="$TMP_ROOT/multi-skill-migration"
cp -R "$FIXTURE" "$MULTI_SKILL_FIXTURE"
jq '.[0].plugin.skills = ["think","write"]' \
  "$MULTI_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json" \
  > "$MULTI_SKILL_FIXTURE/registry.tmp"
mv "$MULTI_SKILL_FIXTURE/registry.tmp" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json"
mkdir -p "$MULTI_SKILL_FIXTURE/home/plugin-roots/claude/waza/skills/write" \
  "$MULTI_SKILL_FIXTURE/home/plugin-roots/codex/waza/skills/write"
printf '# Write\n' > "$MULTI_SKILL_FIXTURE/home/plugin-roots/claude/waza/skills/write/SKILL.md"
printf '# Write\n' > "$MULTI_SKILL_FIXTURE/home/plugin-roots/codex/waza/skills/write/SKILL.md"
seed_multi_skill_duplicates "$MULTI_SKILL_FIXTURE"
HOME="$MULTI_SKILL_FIXTURE/home" TMPDIR="$MULTI_SKILL_FIXTURE/runtime" \
PATH="$MULTI_SKILL_FIXTURE/bin:$PATH" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MULTI_SKILL_FIXTURE/installed.json"
test "$(rg -Fxc 'plugin install waza@waza' \
  "$MULTI_SKILL_FIXTURE/home/claude-mutations.log" || true)" -eq 1
test "$(rg -Fxc 'plugin add waza@waza' \
  "$MULTI_SKILL_FIXTURE/home/codex-mutations.log" || true)" -eq 1
jq -e '
  ([.events[] | select(
    .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "claude" and .action == "install" and .status == "applied"
  ) | .skill] == ["think","write"]) and
  ([.events[] | select(
    .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "codex" and .action == "install" and .status == "applied"
  ) | .skill] == ["think","write"])
' "$MULTI_SKILL_FIXTURE/installed.json" >/dev/null

MULTI_SKILL_NATIVE_FAILURE_FIXTURE="$TMP_ROOT/multi-skill-native-failure"
cp -R "$MULTI_SKILL_FIXTURE" "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE"
jq 'map(.version = "0.9.0")' \
  "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/claude-plugins.json" \
  > "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/claude-plugins.tmp"
mv "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/claude-plugins.tmp" \
  "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/claude-plugins.json"
jq '.installed |= map(.version = "0.9.0")' \
  "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/codex-plugins.json" \
  > "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/codex-plugins.tmp"
mv "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/codex-plugins.tmp" \
  "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/codex-plugins.json"
set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_PLUGIN_UPDATE_VERSION=1.0.0 \
PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home" \
TMPDIR="$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/runtime" \
PATH="$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/bin:$PATH" \
  "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/result.json"
multi_skill_native_failure_exit=$?
set -e
test "$multi_skill_native_failure_exit" -eq 1
jq -e '
  .status == "failed" and .recovery.required == true and
  ([.events[] | select(
    .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "claude" and .action == "update" and .status == "failed"
  ) | .skill] == ["think","write"]) and
  ([.events[] | select(
    .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "codex" and .action == "update" and .status == "applied"
  ) | .skill] == ["think","write"])
' "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/result.json" >/dev/null
test ! -e "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/.claude/skills/think"
test ! -e "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/.claude/skills/write"
test ! -e "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/.agents/skills/think"
test ! -e "$MULTI_SKILL_NATIVE_FAILURE_FIXTURE/home/.agents/skills/write"

test ! -e "$MULTI_SKILL_FIXTURE/home/.claude/skills/think"
test ! -e "$MULTI_SKILL_FIXTURE/home/.claude/skills/write"
test ! -e "$MULTI_SKILL_FIXTURE/home/.agents/skills/think"
test ! -e "$MULTI_SKILL_FIXTURE/home/.agents/skills/write"

POST_MIGRATION_REGRESSION_FIXTURE="$TMP_ROOT/post-migration-regression"
cp -R "$MULTI_SKILL_FIXTURE" "$POST_MIGRATION_REGRESSION_FIXTURE"
jq 'map(.version = "0.9.0")' "$POST_MIGRATION_REGRESSION_FIXTURE/home/claude-plugins.json"   > "$POST_MIGRATION_REGRESSION_FIXTURE/claude-plugins.tmp"
mv "$POST_MIGRATION_REGRESSION_FIXTURE/claude-plugins.tmp"   "$POST_MIGRATION_REGRESSION_FIXTURE/home/claude-plugins.json"
jq '.installed |= map(.version = "0.9.0")'   "$POST_MIGRATION_REGRESSION_FIXTURE/home/codex-plugins.json"   > "$POST_MIGRATION_REGRESSION_FIXTURE/codex-plugins.tmp"
mv "$POST_MIGRATION_REGRESSION_FIXTURE/codex-plugins.tmp"   "$POST_MIGRATION_REGRESSION_FIXTURE/home/codex-plugins.json"
set +e
FAKE_PLUGIN_UPDATE_VERSION=1.0.0 FAKE_DROP_SKILL_ON_UPDATE=write HOME="$POST_MIGRATION_REGRESSION_FIXTURE/home" TMPDIR="$POST_MIGRATION_REGRESSION_FIXTURE/runtime" PATH="$POST_MIGRATION_REGRESSION_FIXTURE/bin:$PATH"   "$POST_MIGRATION_REGRESSION_FIXTURE/agent-tooling/update-skill-topology.sh" --json   > "$POST_MIGRATION_REGRESSION_FIXTURE/result.json"
post_migration_regression_exit=$?
set -e
test "$post_migration_regression_exit" -eq 1
test ! -e "$POST_MIGRATION_REGRESSION_FIXTURE/home/.claude/skills/write"
test ! -e "$POST_MIGRATION_REGRESSION_FIXTURE/home/.agents/skills/write"
jq -e '
  .status == "failed" and .state == "failed" and .idempotent == false and
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  any(.migrations[]; .skill == "write" and .gate == "blocked" and
    all(.copies[]; .state == "absent" and .action == "none")) and
  ([.events[] | select(.kind == "runtime-verification" and .skill == "write" and
    .status == "failed" and .reason == "error") | .destination] == ["claude","codex"]) and
  ([.events[] | select(.kind == "copy-retained" or .kind == "copy-removal")] == []) and
  any(.events[]; .kind == "blocking-failure")
' "$POST_MIGRATION_REGRESSION_FIXTURE/result.json" >/dev/null

seed_multi_skill_duplicates "$MULTI_SKILL_FIXTURE"
jq 'map(.version = "0.9.0")' "$MULTI_SKILL_FIXTURE/home/claude-plugins.json" \
  > "$MULTI_SKILL_FIXTURE/claude-plugins.tmp"
mv "$MULTI_SKILL_FIXTURE/claude-plugins.tmp" "$MULTI_SKILL_FIXTURE/home/claude-plugins.json"
jq '.installed |= map(.version = "0.9.0")' "$MULTI_SKILL_FIXTURE/home/codex-plugins.json" \
  > "$MULTI_SKILL_FIXTURE/codex-plugins.tmp"
mv "$MULTI_SKILL_FIXTURE/codex-plugins.tmp" "$MULTI_SKILL_FIXTURE/home/codex-plugins.json"
: > "$MULTI_SKILL_FIXTURE/home/claude-mutations.log"
: > "$MULTI_SKILL_FIXTURE/home/codex-mutations.log"
set +e
FAKE_PLUGIN_UPDATE_VERSION=1.0.0 FAKE_DROP_SKILL_ON_UPDATE=write \
HOME="$MULTI_SKILL_FIXTURE/home" TMPDIR="$MULTI_SKILL_FIXTURE/runtime" \
PATH="$MULTI_SKILL_FIXTURE/bin:$PATH" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MULTI_SKILL_FIXTURE/withdrawn.json"
multi_skill_exit=$?
set -e
test "$multi_skill_exit" -eq 1
test "$(rg -Fxc 'plugin update waza@waza' \
  "$MULTI_SKILL_FIXTURE/home/claude-mutations.log" || true)" -eq 1
test "$(rg -Fxc 'plugin add waza@waza' \
  "$MULTI_SKILL_FIXTURE/home/codex-mutations.log" || true)" -eq 1
test ! -e "$MULTI_SKILL_FIXTURE/home/.claude/skills/think"
test ! -e "$MULTI_SKILL_FIXTURE/home/.agents/skills/think"
test -f "$MULTI_SKILL_FIXTURE/home/.claude/skills/write/SKILL.md"
test -f "$MULTI_SKILL_FIXTURE/home/.agents/skills/write/SKILL.md"
jq -e '
  .status == "failed" and
  any(.migrations[]; .skill == "think" and .gate == "verified") and
  any(.migrations[]; .skill == "write" and .gate == "blocked") and
  ([.changes[] | select(.action == "copy-removed" and .skill == "think") | .destination]
    == ["claude","codex"]) and
  ([.changes[] | select(.action == "copy-removed" and .skill == "write")] == [])
' "$MULTI_SKILL_FIXTURE/withdrawn.json" >/dev/null

if ! HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/first.json"; then
  cat "$FIXTURE/first.json" >&2
  exit 1
fi
jq -e '
  .status == "reconciled" and
  ([.plan[] | {sourceId, skill, destinations}] == [{
    "sourceId":"waza",
    "skill":"waza",
    "destinations":["claude","codex"]
  }]) and
  ([.changes[] | {action, sourceId, skill, destination}] == [
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"claude"},
    {"action":"installed","sourceId":"waza","skill":"waza","destination":"codex"}
  ]) and
  .errors == [] and .decisions == []
' "$FIXTURE/first.json" >/dev/null
grep -Fx 'plugin marketplace add tw93/Waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin install waza@waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin marketplace add tw93/Waza' "$FIXTURE/home/codex-mutations.log" >/dev/null
grep -Fx 'plugin add waza@waza' "$FIXTURE/home/codex-mutations.log" >/dev/null

cp "$FIXTURE/home/claude-mutations.log" "$FIXTURE/claude-mutations-before-check"
cp "$FIXTURE/home/codex-mutations.log" "$FIXTURE/codex-mutations-before-check"
HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --check --json > "$FIXTURE/check.json"
jq -e '.status == "clean" and .changes == [] and .errors == []' "$FIXTURE/check.json" >/dev/null
cmp -s "$FIXTURE/claude-mutations-before-check" "$FIXTURE/home/claude-mutations.log"
cmp -s "$FIXTURE/codex-mutations-before-check" "$FIXTURE/home/codex-mutations.log"

HOME="$FIXTURE/home" TMPDIR="$FIXTURE/runtime" PATH="$BIN:$PATH" \
  "$COMMAND" --json > "$FIXTURE/second.json"
jq -e '.status == "reconciled" and .changes == [] and .errors == [] and .decisions == []' \
  "$FIXTURE/second.json" >/dev/null
grep -Fx 'plugin marketplace update waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin update waza@waza' "$FIXTURE/home/claude-mutations.log" >/dev/null
grep -Fx 'plugin marketplace upgrade waza' "$FIXTURE/home/codex-mutations.log" >/dev/null

REMOVE_FIXTURE="$TMP_ROOT/remove"
cp -R "$FIXTURE" "$REMOVE_FIXTURE"
jq '.sources[0].defaultDestinations = ["claude"]' \
  "$REMOVE_FIXTURE/agent-tooling/skill-topology.json" > "$REMOVE_FIXTURE/manifest.tmp"
mv "$REMOVE_FIXTURE/manifest.tmp" "$REMOVE_FIXTURE/agent-tooling/skill-topology.json"
HOME="$REMOVE_FIXTURE/home" TMPDIR="$REMOVE_FIXTURE/runtime" PATH="$REMOVE_FIXTURE/bin:$PATH" \
  "$REMOVE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$REMOVE_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  ([.changes[] | {action, destination}] == [{"action":"removed","destination":"codex"}])
' "$REMOVE_FIXTURE/result.json" >/dev/null
jq -e '.installed == []' "$REMOVE_FIXTURE/home/codex-plugins.json" >/dev/null
grep -Fx 'plugin remove waza@waza' "$REMOVE_FIXTURE/home/codex-mutations.log" >/dev/null

UNKNOWN_FIXTURE="$TMP_ROOT/unknown"
cp -R "$FIXTURE" "$UNKNOWN_FIXTURE"
jq -n --arg path "$UNKNOWN_FIXTURE/home/plugin-roots/claude/waza" '
[
  {id:"waza@waza",version:"1.0.0",enabled:true,installPath:$path},
  {id:"frontend-design@claude-plugins-official",version:"1.0.0",enabled:true},
  {id:"rogue@custom-market",version:"1.0.0",enabled:true}
]
' > "$UNKNOWN_FIXTURE/home/claude-plugins.json"
jq -n --arg path "$UNKNOWN_FIXTURE/home/plugin-roots/codex/waza" '
{
  installed: [
    {pluginId:"waza@waza",marketplaceName:"waza",version:"1.0.0",installed:true,enabled:true,source:{source:"local",path:$path}},
    {pluginId:"documents@openai-primary-runtime",marketplaceName:"openai-primary-runtime",version:"1.0.0",installed:true,enabled:true},
    {pluginId:"browser@openai-bundled",marketplaceName:"openai-bundled",version:"1.0.0",installed:true,enabled:true},
    {pluginId:"rogue@custom-market",marketplaceName:"custom-market",version:"1.0.0",installed:true,enabled:true},
    {pluginId:"rogue-openai@openai-community",marketplaceName:"openai-community",version:"1.0.0",installed:true,enabled:true}
  ]
}
' > "$UNKNOWN_FIXTURE/home/codex-plugins.json"
cp "$UNKNOWN_FIXTURE/home/claude-mutations.log" "$UNKNOWN_FIXTURE/claude-mutations-before"
cp "$UNKNOWN_FIXTURE/home/codex-mutations.log" "$UNKNOWN_FIXTURE/codex-mutations-before"
set +e
HOME="$UNKNOWN_FIXTURE/home" TMPDIR="$UNKNOWN_FIXTURE/runtime" PATH="$UNKNOWN_FIXTURE/bin:$PATH" \
  "$UNKNOWN_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$UNKNOWN_FIXTURE/result.json"
unknown_exit=$?
set -e
test "$unknown_exit" -eq 3
if ! jq -e '
  .status == "decision-required" and .changes == [] and
  ([.decisions[] | {code, pluginId, destination}] == [
    {"code":"unknown-installed-plugin","pluginId":"rogue-openai@openai-community","destination":"codex"},
    {"code":"unknown-installed-plugin","pluginId":"rogue@custom-market","destination":"claude"},
    {"code":"unknown-installed-plugin","pluginId":"rogue@custom-market","destination":"codex"}
  ]) and
  ([.decisions[] | select(.pluginId == "frontend-design@claude-plugins-official" or .pluginId == "documents@openai-primary-runtime" or .pluginId == "browser@openai-bundled")] | length) == 0
' "$UNKNOWN_FIXTURE/result.json" >/dev/null; then
  cat "$UNKNOWN_FIXTURE/result.json" >&2
  exit 1
fi
cmp -s "$UNKNOWN_FIXTURE/claude-mutations-before" "$UNKNOWN_FIXTURE/home/claude-mutations.log"
cmp -s "$UNKNOWN_FIXTURE/codex-mutations-before" "$UNKNOWN_FIXTURE/home/codex-mutations.log"

CLAUDE_DISABLED_FIXTURE="$TMP_ROOT/claude-disabled"
cp -R "$FIXTURE" "$CLAUDE_DISABLED_FIXTURE"
jq 'map(if .id == "waza@waza" then .enabled = false else . end)' \
  "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json" > "$CLAUDE_DISABLED_FIXTURE/disabled.tmp"
mv "$CLAUDE_DISABLED_FIXTURE/disabled.tmp" "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json"
HOME="$CLAUDE_DISABLED_FIXTURE/home" TMPDIR="$CLAUDE_DISABLED_FIXTURE/runtime" \
PATH="$CLAUDE_DISABLED_FIXTURE/bin:$PATH" \
  "$CLAUDE_DISABLED_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$CLAUDE_DISABLED_FIXTURE/result.json"
jq -e '.status == "reconciled" and .changes == [] and .errors == []' \
  "$CLAUDE_DISABLED_FIXTURE/result.json" >/dev/null
jq -e '.[0].enabled == false' "$CLAUDE_DISABLED_FIXTURE/home/claude-plugins.json" >/dev/null
test "$(grep -Fxc 'plugin enable waza@waza' "$CLAUDE_DISABLED_FIXTURE/home/claude-mutations.log" || true)" -eq 0

CODEX_DISABLED_FIXTURE="$TMP_ROOT/codex-disabled"
cp -R "$FIXTURE" "$CODEX_DISABLED_FIXTURE"
jq '.installed |= map(if .pluginId == "waza@waza" then .enabled = false else . end)' \
  "$CODEX_DISABLED_FIXTURE/home/codex-plugins.json" > "$CODEX_DISABLED_FIXTURE/disabled.tmp"
mv "$CODEX_DISABLED_FIXTURE/disabled.tmp" "$CODEX_DISABLED_FIXTURE/home/codex-plugins.json"
cat > "$CODEX_DISABLED_FIXTURE/home/.codex/config.toml" <<'TOML'
[plugins."waza@waza"]
enabled = false
TOML
HOME="$CODEX_DISABLED_FIXTURE/home" TMPDIR="$CODEX_DISABLED_FIXTURE/runtime" \
PATH="$CODEX_DISABLED_FIXTURE/bin:$PATH" \
  "$CODEX_DISABLED_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$CODEX_DISABLED_FIXTURE/result.json"
jq -e '.status == "reconciled" and .changes == [] and .errors == []' \
  "$CODEX_DISABLED_FIXTURE/result.json" >/dev/null
HOME="$CODEX_DISABLED_FIXTURE/home" PATH="$CODEX_DISABLED_FIXTURE/bin:$PATH" \
  codex plugin list --json | jq -e '.installed[0].enabled == false' >/dev/null
rg -q '^enabled = false$' "$CODEX_DISABLED_FIXTURE/home/.codex/config.toml"

UPDATE_FIXTURE="$TMP_ROOT/update"
cp -R "$FIXTURE" "$UPDATE_FIXTURE"
jq '.plugins[0].version = "2.0.0"' \
  "$UPDATE_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json" \
  > "$UPDATE_FIXTURE/claude-marketplace.tmp"
mv "$UPDATE_FIXTURE/claude-marketplace.tmp" \
  "$UPDATE_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json"
jq '.version = "2.0.0"' \
  "$UPDATE_FIXTURE/remote-marketplace/plugins/waza/.codex-plugin/plugin.json" \
  > "$UPDATE_FIXTURE/codex-plugin.tmp"
mv "$UPDATE_FIXTURE/codex-plugin.tmp" \
  "$UPDATE_FIXTURE/remote-marketplace/plugins/waza/.codex-plugin/plugin.json"
cp -R "$UPDATE_FIXTURE/home" "$UPDATE_FIXTURE/home-before-check"
set +e
FAKE_GIT_LOG="$UPDATE_FIXTURE/git.log" \
HOME="$UPDATE_FIXTURE/home" TMPDIR="$UPDATE_FIXTURE/runtime" PATH="$UPDATE_FIXTURE/bin:$PATH" \
  "$UPDATE_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json > "$UPDATE_FIXTURE/check.json"
update_check_exit=$?
set -e
test "$update_check_exit" -eq 1
jq -e '
  .status == "drift" and
  ([.drift[] | {sourceId, skill, destination, reason}] == [
    {"sourceId":"waza","skill":"waza","destination":"claude","reason":"outdated: installed 1.0.0, available 2.0.0"},
    {"sourceId":"waza","skill":"waza","destination":"codex","reason":"outdated: installed 1.0.0, available 2.0.0"}
  ]) and
  ([.changes[] | {action, sourceId, skill, destination}] == [
    {"action":"updated","sourceId":"waza","skill":"waza","destination":"claude"},
    {"action":"updated","sourceId":"waza","skill":"waza","destination":"codex"}
  ]) and
  .errors == []
' "$UPDATE_FIXTURE/check.json" >/dev/null
diff -r "$UPDATE_FIXTURE/home-before-check" "$UPDATE_FIXTURE/home" >/dev/null
grep -Eq "^$UPDATE_FIXTURE/runtime/agent-scripts-topology-discovery-.+/waza/repo$" \
  "$UPDATE_FIXTURE/git.log"
set +e
HOME="$UPDATE_FIXTURE/home" TMPDIR="$UPDATE_FIXTURE/runtime" PATH="$UPDATE_FIXTURE/bin:$PATH" \
  "$UPDATE_FIXTURE/agent-tooling/update-skill-topology.sh" --check \
  > "$UPDATE_FIXTURE/check.out" 2> "$UPDATE_FIXTURE/check.err"
update_human_exit=$?
set -e
test "$update_human_exit" -eq 1
grep -Eq '^SOURCE +DESTINATION +CHANGE +RESULT$' "$UPDATE_FIXTURE/check.out"
rg -q '^waza/waza +claude +native-plan:update +planned$' "$UPDATE_FIXTURE/check.out"
rg -q '^waza/waza +codex +native-plan:update +planned$' "$UPDATE_FIXTURE/check.out"
rg -q '^waza/waza +claude +runtime-verification:outdated: installed 1\.0\.0, available 2\.0\.0 +blocked$' \
  "$UPDATE_FIXTURE/check.out"
rg -q '^waza/waza +codex +runtime-verification:outdated: installed 1\.0\.0, available 2\.0\.0 +blocked$' \
  "$UPDATE_FIXTURE/check.out"
! rg -q '^waza/waza +(claude|codex) +updated:outdated:' "$UPDATE_FIXTURE/check.out"
diff -r "$UPDATE_FIXTURE/home-before-check" "$UPDATE_FIXTURE/home" >/dev/null

DISABLED_UPDATE_FIXTURE="$TMP_ROOT/disabled-update"
cp -R "$UPDATE_FIXTURE" "$DISABLED_UPDATE_FIXTURE"
jq 'map(if .id == "waza@waza" then .enabled = false else . end)' \
  "$DISABLED_UPDATE_FIXTURE/home/claude-plugins.json" > "$DISABLED_UPDATE_FIXTURE/claude-disabled.tmp"
mv "$DISABLED_UPDATE_FIXTURE/claude-disabled.tmp" "$DISABLED_UPDATE_FIXTURE/home/claude-plugins.json"
jq '.installed |= map(if .pluginId == "waza@waza" then .enabled = false else . end)' \
  "$DISABLED_UPDATE_FIXTURE/home/codex-plugins.json" > "$DISABLED_UPDATE_FIXTURE/codex-disabled.tmp"
mv "$DISABLED_UPDATE_FIXTURE/codex-disabled.tmp" "$DISABLED_UPDATE_FIXTURE/home/codex-plugins.json"
cat > "$DISABLED_UPDATE_FIXTURE/home/.codex/config.toml" <<'TOML'
[plugins."waza@waza"]
enabled = false

[unrelated]
enabled = false
value = "preserved"
TOML
FAKE_PLUGIN_UPDATE_VERSION=2.0.0 FAKE_CLAUDE_ENABLE_ON_UPDATE=1 \
HOME="$DISABLED_UPDATE_FIXTURE/home" TMPDIR="$DISABLED_UPDATE_FIXTURE/runtime" \
PATH="$DISABLED_UPDATE_FIXTURE/bin:$PATH" \
  "$DISABLED_UPDATE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$DISABLED_UPDATE_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and .errors == [] and
  ([.changes[] | {action, destination}] == [
    {"action":"updated","destination":"claude"},
    {"action":"updated","destination":"codex"}
  ])
' "$DISABLED_UPDATE_FIXTURE/result.json" >/dev/null
jq -e '.[0].version == "2.0.0" and .[0].enabled == false' \
  "$DISABLED_UPDATE_FIXTURE/home/claude-plugins.json" >/dev/null
HOME="$DISABLED_UPDATE_FIXTURE/home" PATH="$DISABLED_UPDATE_FIXTURE/bin:$PATH" \
  codex plugin list --json | jq -e \
  '.installed[0].version == "2.0.0" and .installed[0].enabled == false' >/dev/null
awk '
  $0 == "[plugins.\"waza@waza\"]" { in_plugin = 1; next }
  in_plugin && /^\[/ { exit !found }
  in_plugin && /^enabled = false$/ { found = 1 }
  END { exit !found }
' "$DISABLED_UPDATE_FIXTURE/home/.codex/config.toml"
rg -q '^value = "preserved"$' "$DISABLED_UPDATE_FIXTURE/home/.codex/config.toml"
test "$(grep -Fxc 'plugin enable waza@waza' "$DISABLED_UPDATE_FIXTURE/home/claude-mutations.log" || true)" -eq 0
grep -Fx 'plugin disable waza@waza' "$DISABLED_UPDATE_FIXTURE/home/claude-mutations.log" >/dev/null

FAKE_PLUGIN_UPDATE_VERSION=2.0.0 \
HOME="$UPDATE_FIXTURE/home" TMPDIR="$UPDATE_FIXTURE/runtime" PATH="$UPDATE_FIXTURE/bin:$PATH" \
  "$UPDATE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$UPDATE_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  ([.changes[] | {action, destination}] == [
    {"action":"updated","destination":"claude"},
    {"action":"updated","destination":"codex"}
  ])
' "$UPDATE_FIXTURE/result.json" >/dev/null
jq -e '.[0].version == "2.0.0"' "$UPDATE_FIXTURE/home/claude-plugins.json" >/dev/null
jq -e '.installed[0].version == "2.0.0"' "$UPDATE_FIXTURE/home/codex-plugins.json" >/dev/null
HOME="$UPDATE_FIXTURE/home" TMPDIR="$UPDATE_FIXTURE/runtime" PATH="$UPDATE_FIXTURE/bin:$PATH" \
  "$UPDATE_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json > "$UPDATE_FIXTURE/recheck.json"
jq -e '.status == "clean" and .drift == [] and .changes == [] and .errors == []' \
  "$UPDATE_FIXTURE/recheck.json" >/dev/null

REMOTE_DISCOVERY_FIXTURE="$TMP_ROOT/remote-discovery-failure"
cp -R "$FIXTURE" "$REMOTE_DISCOVERY_FIXTURE"
set +e
FAKE_GIT_CLONE_FAIL=1 \
HOME="$REMOTE_DISCOVERY_FIXTURE/home" TMPDIR="$REMOTE_DISCOVERY_FIXTURE/runtime" \
PATH="$REMOTE_DISCOVERY_FIXTURE/bin:$PATH" \
  "$REMOTE_DISCOVERY_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$REMOTE_DISCOVERY_FIXTURE/result.json"
remote_discovery_exit=$?
set -e
test "$remote_discovery_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("source waza discovery failed") and contains("fixture remote discovery failure"))
' "$REMOTE_DISCOVERY_FIXTURE/result.json" >/dev/null

OUTAGE_FIXTURE="$TMP_ROOT/marketplace-outage"
cp -R "$FIXTURE" "$OUTAGE_FIXTURE"
set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$OUTAGE_FIXTURE/home" TMPDIR="$OUTAGE_FIXTURE/runtime" PATH="$OUTAGE_FIXTURE/bin:$PATH" \
  "$OUTAGE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$OUTAGE_FIXTURE/result.json"
outage_exit=$?
set -e
test "$outage_exit" -eq 1
jq -e '
  .status == "failed" and .state == "failed" and .idempotent == false and
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  all(.migrations[];
    .gate == "verified" and
    all(.native[]; .status == "verified") and
    all(.copies[]; .state == "absent" and .action == "none")) and
  any(.events[]; .kind == "native-reconciliation" and .phase == "apply" and
    .destination == "claude" and .action == "update" and .status == "failed") and
  ([.events[] | select(.kind == "copy-retained" or .kind == "copy-removal")] == [])
' "$OUTAGE_FIXTURE/result.json" >/dev/null
test ! -e "$OUTAGE_FIXTURE/home/.claude/skills/waza"
test ! -e "$OUTAGE_FIXTURE/home/.agents/skills/waza"

jq '.plugins[0].version = "2.0.0"' \
  "$OUTAGE_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json" \
  > "$OUTAGE_FIXTURE/claude-marketplace.tmp"
mv "$OUTAGE_FIXTURE/claude-marketplace.tmp" \
  "$OUTAGE_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json"
jq '.version = "2.0.0"' \
  "$OUTAGE_FIXTURE/remote-marketplace/plugins/waza/.codex-plugin/plugin.json" \
  > "$OUTAGE_FIXTURE/codex-plugin.tmp"
mv "$OUTAGE_FIXTURE/codex-plugin.tmp" \
  "$OUTAGE_FIXTURE/remote-marketplace/plugins/waza/.codex-plugin/plugin.json"
mkdir -p "$OUTAGE_FIXTURE/home/.claude/skills/waza" "$OUTAGE_FIXTURE/home/.agents/skills/waza"
printf '# retained Claude copy\n' > "$OUTAGE_FIXTURE/home/.claude/skills/waza/SKILL.md"
printf '# retained Codex copy\n' > "$OUTAGE_FIXTURE/home/.agents/skills/waza/SKILL.md"
cp "$OUTAGE_FIXTURE/home/.claude/skills/waza/SKILL.md" "$OUTAGE_FIXTURE/claude-copy.before"
cp "$OUTAGE_FIXTURE/home/.agents/skills/waza/SKILL.md" "$OUTAGE_FIXTURE/codex-copy.before"
set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_PLUGIN_UPDATE_VERSION=2.0.0 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$OUTAGE_FIXTURE/home" TMPDIR="$OUTAGE_FIXTURE/runtime" PATH="$OUTAGE_FIXTURE/bin:$PATH" \
  "$OUTAGE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$OUTAGE_FIXTURE/copies.json"
outage_copies_exit=$?
set -e
test "$outage_copies_exit" -eq 1
jq -e '
  .status == "failed" and
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery.required == true and
  all(.migrations[];
    .gate == "blocked" and
    ([.native[] | .status] == ["outdated","verified"]) and
    all(.copies[]; .state == "present" and .action == "retain")) and
  any(.events[]; .kind == "native-reconciliation" and .destination == "claude" and
    .action == "update" and .status == "failed") and
  ([.events[] | select(.kind == "copy-retained") | .destination] == ["claude","codex"]) and
  ([.events[] | select(.kind == "copy-removal")] == [])
' "$OUTAGE_FIXTURE/copies.json" >/dev/null
cmp -s "$OUTAGE_FIXTURE/claude-copy.before" "$OUTAGE_FIXTURE/home/.claude/skills/waza/SKILL.md"
cmp -s "$OUTAGE_FIXTURE/codex-copy.before" "$OUTAGE_FIXTURE/home/.agents/skills/waza/SKILL.md"

FAILURE_FIXTURE="$TMP_ROOT/failure"
cp -R "$FIXTURE" "$FAILURE_FIXTURE"
printf '{"installed":[]}\n' > "$FAILURE_FIXTURE/home/codex-plugins.json"
set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_CODEX_INSTALL_FAIL=1 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$FAILURE_FIXTURE/home" TMPDIR="$FAILURE_FIXTURE/runtime" PATH="$FAILURE_FIXTURE/bin:$PATH" \
  "$FAILURE_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$FAILURE_FIXTURE/result.json"
failure_exit=$?
set -e
test "$failure_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("Claude marketplace update failed") and contains("fixture Claude marketplace failure")) and
  any(.errors[]; contains("Codex plugin install failed") and contains("fixture Codex install failure")) and
  any(.errors[]; contains("final verification failed: waza/waza -> codex: missing"))
' "$FAILURE_FIXTURE/result.json" >/dev/null

set +e
FAKE_CLAUDE_MARKETPLACE_FAIL=1 FAKE_CODEX_INSTALL_FAIL=1 PLUGIN_RETRY_DELAY_SECONDS=0 \
HOME="$FAILURE_FIXTURE/home" TMPDIR="$FAILURE_FIXTURE/runtime" PATH="$FAILURE_FIXTURE/bin:$PATH" \
  "$FAILURE_FIXTURE/agent-tooling/update-skill-topology.sh" > "$FAILURE_FIXTURE/human.out" 2> "$FAILURE_FIXTURE/human.err"
failure_human_exit=$?
set -e
test "$failure_human_exit" -eq 1
grep -F 'error: source waza reconciliation failed: Claude marketplace update failed' "$FAILURE_FIXTURE/human.err" >/dev/null
grep -F 'error: source waza reconciliation failed: Codex plugin install failed' "$FAILURE_FIXTURE/human.err" >/dev/null
grep -F 'error: final verification failed: waza/waza -> codex: missing' "$FAILURE_FIXTURE/human.err" >/dev/null

jq -e '
  ([.sources[] | select(.id == "waza" or .id == "claude-mem") | {
    id, classification, defaultDestinations
  }] | length) == 2 and
  all(.sources[] | select(.id == "waza" or .id == "claude-mem");
    .classification == "dual-plugin" and
    .defaultDestinations == ["claude","codex"] and
    (has("overrides") | not))
' "$REPO_ROOT/agent-tooling/skill-topology.json" >/dev/null

MEM_FIXTURE="$TMP_ROOT/claude-mem"
MEM_BIN="$MEM_FIXTURE/bin"
mkdir -p "$MEM_FIXTURE/agent-tooling" "$MEM_FIXTURE/home/.bun/bin" "$MEM_FIXTURE/home/.local/bin" \
  "$MEM_FIXTURE/home/.claude-mem" "$MEM_FIXTURE/home/.claude/skills" "$MEM_FIXTURE/runtime" "$MEM_BIN" \
  "$MEM_FIXTURE/home/claude-marketplace/.claude-plugin" \
  "$MEM_FIXTURE/home/codex-marketplace/.agents/plugins" \
  "$MEM_FIXTURE/home/codex-marketplace/plugin/.codex-plugin" \
  "$MEM_FIXTURE/remote-marketplace/.claude-plugin" \
  "$MEM_FIXTURE/remote-marketplace/.agents/plugins" \
  "$MEM_FIXTURE/remote-marketplace/plugin/.codex-plugin"
cp "$REPO_ROOT/agent-tooling/update-skill-topology.sh" "$MEM_FIXTURE/agent-tooling/"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$MEM_FIXTURE/agent-tooling/"
jq '{version, sources: [.sources[] | select(.id == "claude-mem")]}' \
  "$REPO_ROOT/agent-tooling/skill-topology.json" > "$MEM_FIXTURE/agent-tooling/skill-topology.json"
jq '[.[] | select(.sourceId == "claude-mem")]' \
  "$REPO_ROOT/agent-tooling/distribution-topology/registry.json" \
  > "$MEM_FIXTURE/agent-tooling/distribution-topology/registry.json"
printf 'claude-skills\n' > "$MEM_FIXTURE/home/.claude/skills/.agent-scripts-root"
printf 'shared database fixture\n' > "$MEM_FIXTURE/home/.claude-mem/database.sqlite"
cp "$MEM_FIXTURE/home/.claude-mem/database.sqlite" "$MEM_FIXTURE/database-before"
printf '[]\n' > "$MEM_FIXTURE/home/claude-plugins.json"
printf '[{"name":"thedotmack"}]\n' > "$MEM_FIXTURE/home/claude-marketplaces.json"
printf '{"installed":[]}\n' > "$MEM_FIXTURE/home/codex-plugins.json"
printf '{"marketplaces":[{"name":"claude-mem-local"}]}\n' > "$MEM_FIXTURE/home/codex-marketplaces.json"
cat > "$MEM_FIXTURE/home/claude-marketplace/.claude-plugin/marketplace.json" <<'JSON'
{"name":"thedotmack","plugins":[{"name":"claude-mem","version":"1.0.0","source":"./plugin"}]}
JSON
cat > "$MEM_FIXTURE/home/codex-marketplace/.agents/plugins/marketplace.json" <<'JSON'
{"name":"claude-mem-local","plugins":[{"name":"claude-mem","source":{"source":"local","path":"./plugin"}}]}
JSON
cat > "$MEM_FIXTURE/home/codex-marketplace/plugin/.codex-plugin/plugin.json" <<'JSON'
{"name":"claude-mem","version":"1.0.0"}
JSON
cp "$MEM_FIXTURE/home/claude-marketplace/.claude-plugin/marketplace.json" \
  "$MEM_FIXTURE/remote-marketplace/.claude-plugin/marketplace.json"
cp "$MEM_FIXTURE/home/codex-marketplace/.agents/plugins/marketplace.json" \
  "$MEM_FIXTURE/remote-marketplace/.agents/plugins/marketplace.json"
cp "$MEM_FIXTURE/home/codex-marketplace/plugin/.codex-plugin/plugin.json" \
  "$MEM_FIXTURE/remote-marketplace/plugin/.codex-plugin/plugin.json"

cat > "$MEM_BIN/dependency" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$0")" >> "$HOME/dependency-calls.log"
printf '1.0.0\n'
BASH
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.bun/bin/bun"
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.local/bin/uv"
cp "$MEM_BIN/dependency" "$MEM_FIXTURE/home/.local/bin/uvx"
chmod +x "$MEM_FIXTURE/home/.bun/bin/bun" "$MEM_FIXTURE/home/.local/bin/uv" \
  "$MEM_FIXTURE/home/.local/bin/uvx"

cat > "$MEM_BIN/claude" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    jq --arg path "$HOME/plugin-roots/claude/claude-mem" '
      map(if .id == "claude-mem@thedotmack" then .installPath = $path else . end)
    ' "$HOME/claude-plugins.json"
    ;;
  'plugin marketplace list --json')
    jq --arg root "$HOME/claude-marketplace" 'map(. + {installLocation:$root})' \
      "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace add thedotmack/claude-mem')
    printf '[{"name":"thedotmack"}]\n' > "$HOME/claude-marketplaces.json"
    ;;
  'plugin marketplace update thedotmack') ;;
  'plugin install claude-mem@thedotmack')
    if [ "${FAKE_MEM_NO_STATE:-0}" != 1 ]; then
      mkdir -p "$HOME/plugin-roots/claude/claude-mem/skills/mem-search"
      printf '# mem-search\n' > "$HOME/plugin-roots/claude/claude-mem/skills/mem-search/SKILL.md"
      jq -n --arg path "$HOME/plugin-roots/claude/claude-mem" \
        '[{id:"claude-mem@thedotmack",version:"1.0.0",enabled:true,installPath:$path}]' \
        > "$HOME/claude-plugins.json"
    fi
    ;;
  'plugin update claude-mem@thedotmack') ;;
  *)
    printf 'unexpected claude-mem Claude call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$MEM_BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'plugin list --json')
    jq --arg path "$HOME/plugin-roots/codex/claude-mem" '
      .installed |= map(
        if .pluginId == "claude-mem@claude-mem-local" then
          .source = ((.source // {}) + {source:"local", path:$path})
        else . end
      )
    ' "$HOME/codex-plugins.json"
    ;;
  'plugin marketplace list --json')
    jq --arg root "$HOME/codex-marketplace" '.marketplaces |= map(. + {root:$root})' \
      "$HOME/codex-marketplaces.json"
    ;;
  'plugin marketplace add thedotmack/claude-mem')
    printf '{"marketplaces":[{"name":"claude-mem-local"}]}\n' > "$HOME/codex-marketplaces.json"
    ;;
  'plugin marketplace upgrade claude-mem-local') ;;
  'plugin add claude-mem@claude-mem-local')
    if [ "${FAKE_MEM_NO_STATE:-0}" != 1 ]; then
      mkdir -p "$HOME/plugin-roots/codex/claude-mem/skills/mem-search"
      printf '# mem-search\n' > "$HOME/plugin-roots/codex/claude-mem/skills/mem-search/SKILL.md"
      jq -n --arg path "$HOME/plugin-roots/codex/claude-mem" \
        '{installed:[{pluginId:"claude-mem@claude-mem-local",marketplaceName:"claude-mem-local",version:"1.0.0",installed:true,enabled:true,source:{source:"local",path:$path}}]}' \
        > "$HOME/codex-plugins.json"
    fi
    ;;
  *)
    printf 'unexpected claude-mem Codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH

cat > "$MEM_BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
test "$#" -eq 6
test "$1" = clone
test "$2" = --depth
test "$3" = 1
test "$4" = --quiet
test "$5" = https://github.com/thedotmack/claude-mem.git
destination="$6"
mkdir -p "$destination"
cp -R "${HOME%/home}/remote-marketplace/." "$destination"
BASH
chmod +x "$MEM_BIN/claude" "$MEM_BIN/codex" "$MEM_BIN/git"

MEM_VERIFY_FIXTURE="$TMP_ROOT/claude-mem-verify"
cp -R "$MEM_FIXTURE" "$MEM_VERIFY_FIXTURE"

HOME="$MEM_FIXTURE/home" TMPDIR="$MEM_FIXTURE/runtime" PATH="$MEM_BIN:$PATH" \
  "$MEM_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$MEM_FIXTURE/result.json"
jq -e '
  .status == "reconciled" and
  (.plan[] | .sourceId == "claude-mem" and .skill == "claude-mem" and .destinations == ["claude","codex"]) and
  ([.changes[] | select(.action == "installed") | .destination] == ["claude","codex"]) and
  .errors == []
' "$MEM_FIXTURE/result.json" >/dev/null
test "$(sort -u "$MEM_FIXTURE/home/dependency-calls.log")" = "$(printf '%s\n' bun uv uvx | sort)"
cmp -s "$MEM_FIXTURE/database-before" "$MEM_FIXTURE/home/.claude-mem/database.sqlite"

set +e
FAKE_MEM_NO_STATE=1 \
HOME="$MEM_VERIFY_FIXTURE/home" TMPDIR="$MEM_VERIFY_FIXTURE/runtime" PATH="$MEM_VERIFY_FIXTURE/bin:$PATH" \
  "$MEM_VERIFY_FIXTURE/agent-tooling/update-skill-topology.sh" --json > "$MEM_VERIFY_FIXTURE/result.json"
mem_verify_exit=$?
set -e
test "$mem_verify_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("remains missing after install")) and
  any(.errors[]; contains("source claude-mem verification failed")) and
  any(.errors[]; contains("final verification failed: claude-mem/claude-mem"))
' "$MEM_VERIFY_FIXTURE/result.json" >/dev/null
cmp -s "$MEM_VERIFY_FIXTURE/database-before" "$MEM_VERIFY_FIXTURE/home/.claude-mem/database.sqlite"


# Runtime skill discovery: plugin installed but expected skill omitted on both CLIs.
MISSING_RUNTIME_SKILL_FIXTURE="$TMP_ROOT/missing-runtime-skill"
cp -R "$FIXTURE" "$MISSING_RUNTIME_SKILL_FIXTURE"
jq --arg path "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/claude/waza" \
  'map(if .id == "waza@waza" then .installPath = $path else . end)' \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/claude-plugins.json" \
  > "$MISSING_RUNTIME_SKILL_FIXTURE/claude-plugins.tmp"
mv "$MISSING_RUNTIME_SKILL_FIXTURE/claude-plugins.tmp" \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/claude-plugins.json"
jq --arg path "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/codex/waza" \
  '.installed |= map(if .pluginId == "waza@waza" then .source = {source:"local",path:$path} else . end)' \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/codex-plugins.json" \
  > "$MISSING_RUNTIME_SKILL_FIXTURE/codex-plugins.tmp"
mv "$MISSING_RUNTIME_SKILL_FIXTURE/codex-plugins.tmp" \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/codex-plugins.json"
rm -rf "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/claude/waza/skills" \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/codex/waza/skills"
mkdir -p "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/claude/waza" \
  "$MISSING_RUNTIME_SKILL_FIXTURE/home/plugin-roots/codex/waza"
cp -R "$MISSING_RUNTIME_SKILL_FIXTURE/home" "$MISSING_RUNTIME_SKILL_FIXTURE/home-before-check"
set +e
HOME="$MISSING_RUNTIME_SKILL_FIXTURE/home" TMPDIR="$MISSING_RUNTIME_SKILL_FIXTURE/runtime" \
PATH="$MISSING_RUNTIME_SKILL_FIXTURE/bin:$PATH" \
  "$MISSING_RUNTIME_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$MISSING_RUNTIME_SKILL_FIXTURE/check.json"
missing_runtime_check_exit=$?
set -e
test "$missing_runtime_check_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("cannot verify waza/waza on claude")
    and contains("expected skill not discoverable in installed plugin")) and
  any(.errors[]; contains("cannot verify waza/waza on codex")
    and contains("expected skill not discoverable in installed plugin"))
' "$MISSING_RUNTIME_SKILL_FIXTURE/check.json" >/dev/null
diff -r "$MISSING_RUNTIME_SKILL_FIXTURE/home-before-check" "$MISSING_RUNTIME_SKILL_FIXTURE/home" >/dev/null

# Multi-skill bundle: one declared expected skill missing from runtime inventory.
MULTI_SKILL_FIXTURE="$TMP_ROOT/multi-skill-bundle"
cp -R "$FIXTURE" "$MULTI_SKILL_FIXTURE"
jq '.[0].plugin.skills = ["waza","ghost-skill"]' \
  "$MULTI_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json" \
  > "$MULTI_SKILL_FIXTURE/registry.tmp"
mv "$MULTI_SKILL_FIXTURE/registry.tmp" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json"
# Keep real component skill "think" so bundle identity "waza" still resolves;
# ghost-skill is absent from both install roots.
mkdir -p "$MULTI_SKILL_FIXTURE/home/plugin-roots/claude/waza/skills/think" \
  "$MULTI_SKILL_FIXTURE/home/plugin-roots/codex/waza/skills/think" \
  "$MULTI_SKILL_FIXTURE/home/.claude/skills/waza" "$MULTI_SKILL_FIXTURE/home/.claude/skills/ghost-skill" \
  "$MULTI_SKILL_FIXTURE/home/.agents/skills/waza" \
  "$MULTI_SKILL_FIXTURE/home/.agents/skills/ghost-skill"
printf '# Waza think\n' > "$MULTI_SKILL_FIXTURE/home/plugin-roots/claude/waza/skills/think/SKILL.md"
printf '# Waza think\n' > "$MULTI_SKILL_FIXTURE/home/plugin-roots/codex/waza/skills/think/SKILL.md"
printf '# duplicate\n' > "$MULTI_SKILL_FIXTURE/home/.claude/skills/waza/SKILL.md"
printf '# duplicate\n' > "$MULTI_SKILL_FIXTURE/home/.claude/skills/ghost-skill/SKILL.md"
printf '# duplicate\n' > "$MULTI_SKILL_FIXTURE/home/.agents/skills/waza/SKILL.md"
printf '# duplicate\n' > "$MULTI_SKILL_FIXTURE/home/.agents/skills/ghost-skill/SKILL.md"
jq --arg path "$MULTI_SKILL_FIXTURE/home/plugin-roots/claude/waza" \
  'map(if .id == "waza@waza" then .installPath = $path else . end)' \
  "$MULTI_SKILL_FIXTURE/home/claude-plugins.json" > "$MULTI_SKILL_FIXTURE/claude-plugins.tmp"
mv "$MULTI_SKILL_FIXTURE/claude-plugins.tmp" "$MULTI_SKILL_FIXTURE/home/claude-plugins.json"
jq --arg path "$MULTI_SKILL_FIXTURE/home/plugin-roots/codex/waza" \
  '.installed |= map(if .pluginId == "waza@waza" then .source = {source:"local",path:$path} else . end)' \
  "$MULTI_SKILL_FIXTURE/home/codex-plugins.json" > "$MULTI_SKILL_FIXTURE/codex-plugins.tmp"
mv "$MULTI_SKILL_FIXTURE/codex-plugins.tmp" "$MULTI_SKILL_FIXTURE/home/codex-plugins.json"
set +e
HOME="$MULTI_SKILL_FIXTURE/home" TMPDIR="$MULTI_SKILL_FIXTURE/runtime" \
PATH="$MULTI_SKILL_FIXTURE/bin:$PATH" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$MULTI_SKILL_FIXTURE/check.json"
multi_skill_exit=$?
set -e
test "$multi_skill_exit" -eq 1
jq -e '
  .status == "failed" and
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  any(.errors[]; contains("cannot verify waza/ghost-skill on claude")
    and contains("expected skill not discoverable in installed plugin")) and
  any(.errors[]; contains("cannot verify waza/ghost-skill on codex")
    and contains("expected skill not discoverable in installed plugin")) and
  all(.errors[]; contains("ghost-skill") or (contains("waza/waza") | not))
' "$MULTI_SKILL_FIXTURE/check.json" >/dev/null
test -f "$MULTI_SKILL_FIXTURE/home/.claude/skills/waza/SKILL.md"
test -f "$MULTI_SKILL_FIXTURE/home/.agents/skills/waza/SKILL.md"
test -f "$MULTI_SKILL_FIXTURE/home/.claude/skills/ghost-skill/SKILL.md"
test -f "$MULTI_SKILL_FIXTURE/home/.agents/skills/ghost-skill/SKILL.md"

set +e
HOME="$MULTI_SKILL_FIXTURE/home" TMPDIR="$MULTI_SKILL_FIXTURE/runtime" \
PATH="$MULTI_SKILL_FIXTURE/bin:$PATH" \
  "$MULTI_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --json \
  > "$MULTI_SKILL_FIXTURE/reconcile.json"
multi_skill_reconcile_exit=$?
set -e
test "$multi_skill_reconcile_exit" -eq 1
jq -e '
  .status == "failed" and
  .policy == {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"} and
  .recovery == {
    required:true,
    actions:["upstream-repair","native-rollback","manifest-decision"]
  } and
  ([.changes[] | select(.action == "copy-removed" and .skill == "waza") | .destination]
    == ["claude","codex"]) and
  ([.changes[] | select(.action == "copy-removed" and .skill == "ghost-skill")] == []) and
  any(.migrations[]; .skill == "waza" and .gate == "verified" and
    all(.copies[]; .state == "absent" and .action == "none")) and
  any(.migrations[]; .skill == "ghost-skill" and .gate == "blocked" and
    all(.copies[]; .state == "present" and .action == "retain"))
' "$MULTI_SKILL_FIXTURE/reconcile.json" >/dev/null
test ! -e "$MULTI_SKILL_FIXTURE/home/.claude/skills/waza"
test ! -e "$MULTI_SKILL_FIXTURE/home/.agents/skills/waza"
test -f "$MULTI_SKILL_FIXTURE/home/.claude/skills/ghost-skill/SKILL.md"
test -f "$MULTI_SKILL_FIXTURE/home/.agents/skills/ghost-skill/SKILL.md"

# Exact component skill identity succeeds when present on both CLIs.
COMPONENT_SKILL_FIXTURE="$TMP_ROOT/component-skill"
cp -R "$FIXTURE" "$COMPONENT_SKILL_FIXTURE"
jq '.[0].plugin.skills = ["think"]' \
  "$COMPONENT_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json" \
  > "$COMPONENT_SKILL_FIXTURE/registry.tmp"
mv "$COMPONENT_SKILL_FIXTURE/registry.tmp" \
  "$COMPONENT_SKILL_FIXTURE/agent-tooling/distribution-topology/registry.json"
jq --arg path "$COMPONENT_SKILL_FIXTURE/home/plugin-roots/claude/waza" \
  'map(if .id == "waza@waza" then .installPath = $path else . end)' \
  "$COMPONENT_SKILL_FIXTURE/home/claude-plugins.json" > "$COMPONENT_SKILL_FIXTURE/claude-plugins.tmp"
mv "$COMPONENT_SKILL_FIXTURE/claude-plugins.tmp" "$COMPONENT_SKILL_FIXTURE/home/claude-plugins.json"
jq --arg path "$COMPONENT_SKILL_FIXTURE/home/plugin-roots/codex/waza" \
  '.installed |= map(if .pluginId == "waza@waza" then .source = {source:"local",path:$path} else . end)' \
  "$COMPONENT_SKILL_FIXTURE/home/codex-plugins.json" > "$COMPONENT_SKILL_FIXTURE/codex-plugins.tmp"
mv "$COMPONENT_SKILL_FIXTURE/codex-plugins.tmp" "$COMPONENT_SKILL_FIXTURE/home/codex-plugins.json"
HOME="$COMPONENT_SKILL_FIXTURE/home" TMPDIR="$COMPONENT_SKILL_FIXTURE/runtime" \
PATH="$COMPONENT_SKILL_FIXTURE/bin:$PATH" \
  "$COMPONENT_SKILL_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$COMPONENT_SKILL_FIXTURE/check.json"
jq -e '
  .status == "clean" and
  ([.plan[] | {sourceId,skill,destinations}] == [
    {sourceId:"waza",skill:"think",destinations:["claude","codex"]}
  ]) and
  .errors == []
' "$COMPONENT_SKILL_FIXTURE/check.json" >/dev/null

# Native marketplace identifiers may differ while sharing one bundle name.
DIFFERENT_IDENTIFIERS_FIXTURE="$TMP_ROOT/different-identifiers"
cp -R "$FIXTURE" "$DIFFERENT_IDENTIFIERS_FIXTURE"
jq '.[0].plugin.identifiers = {claude:"waza-claude",codex:"waza-codex"}' \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/agent-tooling/distribution-topology/registry.json" \
  > "$DIFFERENT_IDENTIFIERS_FIXTURE/registry.tmp"
mv "$DIFFERENT_IDENTIFIERS_FIXTURE/registry.tmp" \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/agent-tooling/distribution-topology/registry.json"
perl -pi -e 's/waza\@waza/waza-claude\@waza/g' "$DIFFERENT_IDENTIFIERS_FIXTURE/bin/claude"
perl -pi -e 's/waza\@waza/waza-claude\@waza/g' \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/home/claude-plugins.json" \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/home/.codex/config.toml"
perl -pi -e 's/waza\@waza/waza-codex\@waza/g' "$DIFFERENT_IDENTIFIERS_FIXTURE/bin/codex"
perl -pi -e 's/waza\@waza/waza-codex\@waza/g' \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/home/codex-plugins.json"
HOME="$DIFFERENT_IDENTIFIERS_FIXTURE/home" TMPDIR="$DIFFERENT_IDENTIFIERS_FIXTURE/runtime" \
PATH="$DIFFERENT_IDENTIFIERS_FIXTURE/bin:$PATH" \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$DIFFERENT_IDENTIFIERS_FIXTURE/check.json"
jq -e '.status == "clean" and .errors == []' \
  "$DIFFERENT_IDENTIFIERS_FIXTURE/check.json" >/dev/null

# Missing install root => skill discovery fails closed after plugin listing success.
NO_INSTALL_PATH_FIXTURE="$TMP_ROOT/no-install-path"
cp -R "$FIXTURE" "$NO_INSTALL_PATH_FIXTURE"
rm -rf "$NO_INSTALL_PATH_FIXTURE/home/plugin-roots"
set +e
HOME="$NO_INSTALL_PATH_FIXTURE/home" TMPDIR="$NO_INSTALL_PATH_FIXTURE/runtime" \
PATH="$NO_INSTALL_PATH_FIXTURE/bin:$PATH" \
  "$NO_INSTALL_PATH_FIXTURE/agent-tooling/update-skill-topology.sh" --check --json \
  > "$NO_INSTALL_PATH_FIXTURE/check.json"
no_path_exit=$?
set -e
test "$no_path_exit" -eq 1
jq -e '
  .status == "failed" and
  any(.errors[]; contains("cannot verify waza/waza on claude")
    and contains("install path is missing")) and
  any(.errors[]; contains("cannot verify waza/waza on codex")
    and contains("install path is missing"))
' "$NO_INSTALL_PATH_FIXTURE/check.json" >/dev/null

echo "plugin-distributed topology tests passed"
