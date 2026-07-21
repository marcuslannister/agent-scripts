#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND="$REPO_ROOT/scripts/update-skill-topology.sh"
TMP_ROOT="$(mktemp -d)"
REAL_JQ="$(command -v jq)"
trap 'rm -rf "$TMP_ROOT"' EXIT

source "$REPO_ROOT/scripts/lib-copies.sh"

install_repo_copy() {
  local destination="$1"
  local source_path="$2"
  local marker_source="${3:-$source_path}"
  local stored_hash

  install_skill_copy "$source_path" "$destination" repo-skills
  if [ "$marker_source" != "$source_path" ]; then
    stored_hash="$(sed -n '3p' "$destination/.agent-scripts-copy")"
    printf '%s\n%s\n%s\n' "$marker_source" repo-skills "$stored_hash" > "$destination/.agent-scripts-copy"
  fi
}

help_output="$($COMMAND --help)"
grep -F 'Usage: update-skill-topology.sh [--check] [--json]' <<< "$help_output" >/dev/null
grep -F '0   reconciled or check clean' <<< "$help_output" >/dev/null
grep -F '1   drift or verification failure' <<< "$help_output" >/dev/null
grep -F '2   invalid usage or manifest' <<< "$help_output" >/dev/null
grep -F '3   user decision required' <<< "$help_output" >/dev/null
grep -F '130 interrupted' <<< "$help_output" >/dev/null

test -f "$REPO_ROOT/codex-skills/maintainer-orchestrator/SKILL.md"
test ! -e "$REPO_ROOT/skills/maintainer-orchestrator"
jq -e '
  (.sources[] | select(.id == "repo-claude") |
    .defaultDestinations == ["claude"] and
    (.overrides | length) == 20 and
    ([.overrides[] | select(. != ["claude", "codex"])] | length) == 0 and
    (.overrides | has("codex-first") | not) and
    (.overrides | has("maintainer-orchestrator") | not) and
    (.overrides | has("onecli-gateway") | not)) and
  (.sources[] | select(.id == "repo-codex") |
    .defaultDestinations == ["codex"] and .overrides == {}) and
  (.sources[] | select(.id == "anthropic-skills") |
    .classification == "source-only" and
    .defaultDestinations == ["claude", "codex"] and
    (.overrides == {
      "docx": ["claude", "codex"],
      "frontend-design": ["codex"],
      "pdf": ["claude", "codex"],
      "pptx": ["claude", "codex"],
      "skill-creator": ["codex"],
      "xlsx": ["claude", "codex"]
    }))
' "$REPO_ROOT/skill-topology.json" >/dev/null

make_fixture() {
  local fixture_root="$1"
  mkdir -p \
    "$fixture_root/scripts" \
    "$fixture_root/skills/new-skill" \
    "$fixture_root/skills/shared-skill" \
    "$fixture_root/codex-skills/codex-tool" \
    "$fixture_root/home/.agents/skills/shared-skill" \
    "$fixture_root/home/.agents/skills/codex-tool" \
    "$fixture_root/runtime"
  cp "$COMMAND" "$REPO_ROOT/scripts/lib-copies.sh" "$fixture_root/scripts/"
  cp -R "$REPO_ROOT/scripts/distribution-topology" "$fixture_root/scripts/"
  jq '[.[] | select(.sourceId == "repo-claude" or .sourceId == "repo-codex")]' \
    "$fixture_root/scripts/distribution-topology/registry.json" > "$fixture_root/registry.tmp"
  mv "$fixture_root/registry.tmp" "$fixture_root/scripts/distribution-topology/registry.json"
  printf '%s\n' '---' 'name: new-skill' 'description: "fixture"' '---' > "$fixture_root/skills/new-skill/SKILL.md"
  printf '%s\n' '---' 'name: shared-skill' 'description: "fixture"' '---' > "$fixture_root/skills/shared-skill/SKILL.md"
  printf '%s\n' '---' 'name: codex-tool' 'description: "fixture"' '---' > "$fixture_root/codex-skills/codex-tool/SKILL.md"
  install_repo_copy "$fixture_root/home/.agents/skills/shared-skill" "$fixture_root/skills/shared-skill" "skills/shared-skill"
  install_repo_copy "$fixture_root/home/.agents/skills/codex-tool" "$fixture_root/codex-skills/codex-tool" "codex-skills/codex-tool"
  cat > "$fixture_root/skill-topology.json" <<'JSON'
{
  "version": 1,
  "sources": [
    {
      "id": "repo-claude",
      "classification": "repo-owned",
      "defaultDestinations": ["claude"],
      "overrides": {"shared-skill": ["claude", "codex"]}
    },
    {
      "id": "repo-codex",
      "classification": "repo-owned",
      "defaultDestinations": ["codex"],
      "overrides": {}
    }
  ]
}
JSON
  git -C "$fixture_root" init -q
  git -C "$fixture_root" add skills codex-skills
  mkdir -p "$fixture_root/skills/untracked-third-party"
  printf '%s\n' '---' 'name: untracked-third-party' 'description: "fixture"' '---' > "$fixture_root/skills/untracked-third-party/SKILL.md"
}

FIXTURE_BASE="$TMP_ROOT/fixture-base"
make_fixture "$FIXTURE_BASE"
HOME="$FIXTURE_BASE/home" TMPDIR="$FIXTURE_BASE/runtime" "$FIXTURE_BASE/scripts/update-skill-topology.sh" --check --json > "$TMP_ROOT/fixture-clean.json"
jq -e '
  .status == "clean" and
  (.plan[] | select(.skill == "new-skill") | .destinations == ["claude"]) and
  (.plan[] | select(.skill == "shared-skill") | .destinations == ["claude", "codex"]) and
  (.plan[] | select(.skill == "codex-tool") | .destinations == ["codex"]) and
  ([.plan[].skill] | index("untracked-third-party") | not)
' "$TMP_ROOT/fixture-clean.json" >/dev/null

CRLF_JQ_ROOT="$TMP_ROOT/crlf-jq"
cp -R "$FIXTURE_BASE" "$CRLF_JQ_ROOT"
mkdir -p "$CRLF_JQ_ROOT/bin"
cat > "$CRLF_JQ_ROOT/bin/jq" <<BASH
#!/usr/bin/env bash
set -euo pipefail
binary=0
args=()
for arg in "\$@"; do
  case "\$arg" in
    -b|--binary) binary=1 ;;
    *) args+=("\$arg") ;;
  esac
done
if [ "\$binary" -eq 1 ]; then
  "$REAL_JQ" "\${args[@]}" | sed 's/\r$//'
  exit \$?
fi
"$REAL_JQ" "\${args[@]}" | sed 's/$/\r/'
BASH
chmod +x "$CRLF_JQ_ROOT/bin/jq"
PATH="$CRLF_JQ_ROOT/bin:$PATH" HOME="$CRLF_JQ_ROOT/home" TMPDIR="$CRLF_JQ_ROOT/runtime" \
  "$CRLF_JQ_ROOT/scripts/update-skill-topology.sh" --check --json > "$CRLF_JQ_ROOT/result.json"
jq -e '.status == "clean"' "$CRLF_JQ_ROOT/result.json" >/dev/null

RECONCILE_ROOT="$TMP_ROOT/reconcile"
cp -R "$FIXTURE_BASE" "$RECONCILE_ROOT"
rm -rf "$RECONCILE_ROOT/home/.agents/skills/shared-skill" "$RECONCILE_ROOT/home/.agents/skills/codex-tool"
if ! HOME="$RECONCILE_ROOT/home" TMPDIR="$RECONCILE_ROOT/runtime" "$RECONCILE_ROOT/scripts/update-skill-topology.sh" --json > "$RECONCILE_ROOT/first.json"; then
  cat "$RECONCILE_ROOT/first.json" >&2
  exit 1
fi
jq -e '
  .mode == "reconcile" and
  .status == "reconciled" and
  ([.changes[] | {action, sourceId, skill, destination}] == [
    {"action":"installed","sourceId":"repo-claude","skill":"shared-skill","destination":"codex"},
    {"action":"installed","sourceId":"repo-codex","skill":"codex-tool","destination":"codex"}
  ]) and
  .errors == []
' "$RECONCILE_ROOT/first.json" >/dev/null
cp -R "$RECONCILE_ROOT/home" "$RECONCILE_ROOT/home-after-first"
HOME="$RECONCILE_ROOT/home" TMPDIR="$RECONCILE_ROOT/runtime" "$RECONCILE_ROOT/scripts/update-skill-topology.sh" --json > "$RECONCILE_ROOT/second.json"
jq -e '.mode == "reconcile" and .status == "reconciled" and .changes == [] and .errors == []' "$RECONCILE_ROOT/second.json" >/dev/null
diff -r "$RECONCILE_ROOT/home-after-first" "$RECONCILE_ROOT/home"

CLEANUP_ROOT="$TMP_ROOT/cleanup"
cp -R "$FIXTURE_BASE" "$CLEANUP_ROOT"
mkdir -p \
  "$CLEANUP_ROOT/skills/hand-skill" \
  "$CLEANUP_ROOT/skills/foreign-skill" \
  "$CLEANUP_ROOT/home/.agents/skills/retired-skill"
printf '%s\n' '---' 'name: hand-skill' 'description: "fixture"' '---' > "$CLEANUP_ROOT/skills/hand-skill/SKILL.md"
printf '%s\n' '---' 'name: foreign-skill' 'description: "fixture"' '---' > "$CLEANUP_ROOT/skills/foreign-skill/SKILL.md"
git -C "$CLEANUP_ROOT" add skills/hand-skill/SKILL.md skills/foreign-skill/SKILL.md
install_repo_copy "$CLEANUP_ROOT/home/.agents/skills/new-skill" "$CLEANUP_ROOT/skills/new-skill" "skills/new-skill"
cp -R "$CLEANUP_ROOT/skills/hand-skill" "$CLEANUP_ROOT/home/.agents/skills/hand-skill"
cp -R "$CLEANUP_ROOT/skills/foreign-skill" "$CLEANUP_ROOT/home/.agents/skills/foreign-skill"
printf '%s\n%s\n' skills/foreign-skill other-owner > "$CLEANUP_ROOT/home/.agents/skills/foreign-skill/.agent-scripts-copy"
printf '%s\n' '---' 'name: retired-skill' 'description: "fixture"' '---' > "$CLEANUP_ROOT/home/.agents/skills/retired-skill/SKILL.md"
printf '%s\n%s\n' skills/retired-skill repo-skills > "$CLEANUP_ROOT/home/.agents/skills/retired-skill/.agent-scripts-copy"

HOME="$CLEANUP_ROOT/home" TMPDIR="$CLEANUP_ROOT/runtime" "$CLEANUP_ROOT/scripts/update-skill-topology.sh" --json > "$CLEANUP_ROOT/result.json"
jq -e '
  .status == "reconciled" and
  ([.changes[] | select(.action == "removed") | .skill] == ["new-skill", "retired-skill"]) and
  ([.skipped[] | {skill, reason}] == [
    {"skill":"foreign-skill","reason":"other-owner"},
    {"skill":"hand-skill","reason":"unowned"}
  ]) and
  .decisions == [] and
  .errors == []
' "$CLEANUP_ROOT/result.json" >/dev/null
test ! -e "$CLEANUP_ROOT/home/.agents/skills/new-skill"
test ! -e "$CLEANUP_ROOT/home/.agents/skills/retired-skill"
test -f "$CLEANUP_ROOT/home/.agents/skills/hand-skill/SKILL.md"
test -f "$CLEANUP_ROOT/home/.agents/skills/foreign-skill/SKILL.md"
test -f "$CLEANUP_ROOT/home/.agents/skills/shared-skill/SKILL.md"

SOURCE_MOVE_ROOT="$TMP_ROOT/source-move"
cp -R "$FIXTURE_BASE" "$SOURCE_MOVE_ROOT"
source_move_hash="$(sed -n '3p' "$SOURCE_MOVE_ROOT/home/.agents/skills/codex-tool/.agent-scripts-copy")"
printf '%s\n%s\n%s\n' skills/codex-tool repo-skills "$source_move_hash" > "$SOURCE_MOVE_ROOT/home/.agents/skills/codex-tool/.agent-scripts-copy"
set +e
HOME="$SOURCE_MOVE_ROOT/home" TMPDIR="$SOURCE_MOVE_ROOT/runtime" "$SOURCE_MOVE_ROOT/scripts/update-skill-topology.sh" --check --json > "$SOURCE_MOVE_ROOT/check.json"
source_move_check_exit=$?
set -e
test "$source_move_check_exit" -eq 1
jq -e '.status == "drift" and (.drift[] | .sourceId == "repo-codex" and .skill == "codex-tool" and .reason == "source-mismatch")' "$SOURCE_MOVE_ROOT/check.json" >/dev/null
HOME="$SOURCE_MOVE_ROOT/home" TMPDIR="$SOURCE_MOVE_ROOT/runtime" "$SOURCE_MOVE_ROOT/scripts/update-skill-topology.sh" --json > "$SOURCE_MOVE_ROOT/reconcile.json"
jq -e '.status == "reconciled" and (.changes[] | .action == "installed" and .sourceId == "repo-codex" and .skill == "codex-tool")' "$SOURCE_MOVE_ROOT/reconcile.json" >/dev/null
test "$(cd "$(sed -n '1p' "$SOURCE_MOVE_ROOT/home/.agents/skills/codex-tool/.agent-scripts-copy")" && pwd -P)" = "$(cd "$SOURCE_MOVE_ROOT/codex-skills/codex-tool" && pwd -P)"

HUMAN_CLEANUP_ROOT="$TMP_ROOT/human-cleanup"
cp -R "$FIXTURE_BASE" "$HUMAN_CLEANUP_ROOT"
install_repo_copy "$HUMAN_CLEANUP_ROOT/home/.agents/skills/new-skill" "$HUMAN_CLEANUP_ROOT/skills/new-skill" "skills/new-skill"
HOME="$HUMAN_CLEANUP_ROOT/home" TMPDIR="$HUMAN_CLEANUP_ROOT/runtime" "$HUMAN_CLEANUP_ROOT/scripts/update-skill-topology.sh" > "$HUMAN_CLEANUP_ROOT/result.out" 2> "$HUMAN_CLEANUP_ROOT/result.err"
test ! -s "$HUMAN_CLEANUP_ROOT/result.err"
grep -F 'Skill topology reconcile' "$HUMAN_CLEANUP_ROOT/result.out" >/dev/null
grep -Eq '^SOURCE +DESTINATION +CHANGE +RESULT$' "$HUMAN_CLEANUP_ROOT/result.out"
grep -Eq '^repo-claude/new-skill +codex +removed +changed$' "$HUMAN_CLEANUP_ROOT/result.out"
grep -F 'Result: reconciled (1 changes)' "$HUMAN_CLEANUP_ROOT/result.out" >/dev/null

SPLIT_OWNER_ROOT="$TMP_ROOT/split-owner"
cp -R "$FIXTURE_BASE" "$SPLIT_OWNER_ROOT"
mkdir -p "$SPLIT_OWNER_ROOT/codex-skills/new-skill" "$SPLIT_OWNER_ROOT/home/.agents/skills/new-skill"
cp "$SPLIT_OWNER_ROOT/skills/new-skill/SKILL.md" "$SPLIT_OWNER_ROOT/codex-skills/new-skill/SKILL.md"
git -C "$SPLIT_OWNER_ROOT" add codex-skills/new-skill/SKILL.md
install_repo_copy "$SPLIT_OWNER_ROOT/home/.agents/skills/new-skill" "$SPLIT_OWNER_ROOT/codex-skills/new-skill" "codex-skills/new-skill"
HOME="$SPLIT_OWNER_ROOT/home" TMPDIR="$SPLIT_OWNER_ROOT/runtime" "$SPLIT_OWNER_ROOT/scripts/update-skill-topology.sh" --check --json > "$SPLIT_OWNER_ROOT/result.json"
jq -e '
  .status == "clean" and
  ([.plan[] | select(.skill == "new-skill") | {sourceId, destinations}] == [
    {"sourceId":"repo-claude","destinations":["claude"]},
    {"sourceId":"repo-codex","destinations":["codex"]}
  ])
' "$SPLIT_OWNER_ROOT/result.json" >/dev/null

FOREIGN_ROOT="$TMP_ROOT/foreign-owner"
cp -R "$FIXTURE_BASE" "$FOREIGN_ROOT"
printf '%s\n%s\n' "$FOREIGN_ROOT/skills/shared-skill" other-owner > "$FOREIGN_ROOT/home/.agents/skills/shared-skill/.agent-scripts-copy"
set +e
HOME="$FOREIGN_ROOT/home" TMPDIR="$FOREIGN_ROOT/runtime" "$FOREIGN_ROOT/scripts/update-skill-topology.sh" --check --json > "$FOREIGN_ROOT/result.json" 2> "$FOREIGN_ROOT/result.err"
foreign_exit=$?
set -e
test "$foreign_exit" -eq 3
test ! -s "$FOREIGN_ROOT/result.err"
jq -e '.status == "decision-required" and (.decisions[] | .code == "surface-ownership-collision" and .skill == "shared-skill" and .destination == "codex")' "$FOREIGN_ROOT/result.json" >/dev/null

TAMPER_ROOT="$TMP_ROOT/tampered-copy"
cp -R "$FIXTURE_BASE" "$TAMPER_ROOT"
printf 'tampered\n' >> "$TAMPER_ROOT/home/.agents/skills/shared-skill/SKILL.md"
set +e
HOME="$TAMPER_ROOT/home" TMPDIR="$TAMPER_ROOT/runtime" "$TAMPER_ROOT/scripts/update-skill-topology.sh" --check --json > "$TAMPER_ROOT/result.json" 2> "$TAMPER_ROOT/result.err"
tamper_exit=$?
set -e
test "$tamper_exit" -eq 1
test ! -s "$TAMPER_ROOT/result.err"
jq -e '.status == "drift" and (.drift[] | .skill == "shared-skill" and .destination == "codex" and .reason == "content-mismatch")' "$TAMPER_ROOT/result.json" >/dev/null

VERIFY_AGGREGATE_ROOT="$TMP_ROOT/verification-aggregate"
cp -R "$FIXTURE_BASE" "$VERIFY_AGGREGATE_ROOT"
chmod 000 \
  "$VERIFY_AGGREGATE_ROOT/home/.agents/skills/shared-skill/SKILL.md" \
  "$VERIFY_AGGREGATE_ROOT/home/.agents/skills/codex-tool/SKILL.md"
set +e
HOME="$VERIFY_AGGREGATE_ROOT/home" TMPDIR="$VERIFY_AGGREGATE_ROOT/runtime" \
  "$VERIFY_AGGREGATE_ROOT/scripts/update-skill-topology.sh" --check --json > "$VERIFY_AGGREGATE_ROOT/result.json"
verify_aggregate_exit=$?
set -e
chmod 644 \
  "$VERIFY_AGGREGATE_ROOT/home/.agents/skills/shared-skill/SKILL.md" \
  "$VERIFY_AGGREGATE_ROOT/home/.agents/skills/codex-tool/SKILL.md"
test "$verify_aggregate_exit" -eq 1
jq -e '
  .status == "failed" and (.errors | length) == 2 and
  ([.errors[] | select(contains("repo-claude/shared-skill") or contains("repo-codex/codex-tool"))] | length) == 2 and
  ([.sources[] | select(.result == "failed") | .id] == ["repo-claude", "repo-codex"])
' "$VERIFY_AGGREGATE_ROOT/result.json" >/dev/null

assert_invalid_manifest() {
  local name="$1"
  local jq_filter="$2"
  local fixture_root="$TMP_ROOT/invalid-$name"
  cp -R "$FIXTURE_BASE" "$fixture_root"
  jq "$jq_filter" "$fixture_root/skill-topology.json" > "$fixture_root/manifest.tmp"
  mv "$fixture_root/manifest.tmp" "$fixture_root/skill-topology.json"

  set +e
  HOME="$fixture_root/home" TMPDIR="$fixture_root/runtime" "$fixture_root/scripts/update-skill-topology.sh" --check --json > "$fixture_root/result.json" 2> "$fixture_root/result.err"
  local invalid_exit=$?
  set -e

  test "$invalid_exit" -eq 2
  test ! -s "$fixture_root/result.err"
  jq -e '.status == "invalid" and (.errors | length == 1)' "$fixture_root/result.json" >/dev/null
}

assert_invalid_manifest top-field '.unexpected = true'
assert_invalid_manifest source-field '.sources[0].command = "forbidden"'
assert_invalid_manifest classification '.sources[0].classification = "mystery"'
assert_invalid_manifest duplicate-destination '.sources[0].defaultDestinations = ["claude", "claude"]'
assert_invalid_manifest unknown-destination '.sources[0].overrides["shared-skill"] = ["claude", "mars"]'
assert_invalid_manifest version '.version = 2'
assert_invalid_manifest version-type '.version = "1"'

MALFORMED_ROOT="$TMP_ROOT/invalid-malformed"
cp -R "$FIXTURE_BASE" "$MALFORMED_ROOT"
printf '{\n' > "$MALFORMED_ROOT/skill-topology.json"
set +e
HOME="$MALFORMED_ROOT/home" TMPDIR="$MALFORMED_ROOT/runtime" "$MALFORMED_ROOT/scripts/update-skill-topology.sh" --check --json > "$MALFORMED_ROOT/result.json" 2> "$MALFORMED_ROOT/result.err"
malformed_exit=$?
set -e
test "$malformed_exit" -eq 2
test ! -s "$MALFORMED_ROOT/result.err"
jq -e '.status == "invalid" and (.errors[0] | contains("not valid JSON"))' "$MALFORMED_ROOT/result.json" >/dev/null

run_fixture_json() {
  local fixture_root="$1"
  set +e
  HOME="$fixture_root/home" TMPDIR="$fixture_root/runtime" "$fixture_root/scripts/update-skill-topology.sh" --check --json > "$fixture_root/result.json" 2> "$fixture_root/result.err"
  RUN_EXIT=$?
  set -e
  test ! -s "$fixture_root/result.err"
}

assert_invalid_registry() {
  local name="$1"
  local jq_filter="$2"
  local fixture_root="$TMP_ROOT/invalid-registry-$name"
  cp -R "$FIXTURE_BASE" "$fixture_root"
  jq "$jq_filter" "$fixture_root/scripts/distribution-topology/registry.json" > "$fixture_root/registry.tmp"
  mv "$fixture_root/registry.tmp" "$fixture_root/scripts/distribution-topology/registry.json"

  run_fixture_json "$fixture_root"
  test "$RUN_EXIT" -eq 2
  jq -e '.status == "invalid" and (.errors | length == 1)' "$fixture_root/result.json" >/dev/null
}

assert_invalid_registry state-inspection-null '.[0].stateInspection = null'
assert_invalid_registry state-inspection-false '.[0].stateInspection = false'
assert_invalid_registry command-backslash-traversal '.[0].command = "adapters\\..\\escape.sh"'

MISSING_ADAPTER_ROOT="$TMP_ROOT/missing-adapter"
cp -R "$FIXTURE_BASE" "$MISSING_ADAPTER_ROOT"
jq '.sources[0].id = "manifest-only"' "$MISSING_ADAPTER_ROOT/skill-topology.json" > "$MISSING_ADAPTER_ROOT/manifest.tmp"
mv "$MISSING_ADAPTER_ROOT/manifest.tmp" "$MISSING_ADAPTER_ROOT/skill-topology.json"
run_fixture_json "$MISSING_ADAPTER_ROOT"
test "$RUN_EXIT" -eq 2
jq -e '.status == "invalid" and (.errors[0] | contains("no registered adapter"))' "$MISSING_ADAPTER_ROOT/result.json" >/dev/null

CLASSIFICATION_ROOT="$TMP_ROOT/classification-mismatch"
cp -R "$FIXTURE_BASE" "$CLASSIFICATION_ROOT"
jq '.[0].classification = "plugin-both" | .[0].plugin = {
  "name":"fixture",
  "repo":"fixture/repo",
  "marketplaces":{"claude":"fixture","codex":"fixture"}
}' "$CLASSIFICATION_ROOT/scripts/distribution-topology/registry.json" > "$CLASSIFICATION_ROOT/registry.tmp"
mv "$CLASSIFICATION_ROOT/registry.tmp" "$CLASSIFICATION_ROOT/scripts/distribution-topology/registry.json"
run_fixture_json "$CLASSIFICATION_ROOT"
test "$RUN_EXIT" -eq 2
jq -e '.status == "invalid" and (.errors[0] | contains("classification mismatch"))' "$CLASSIFICATION_ROOT/result.json" >/dev/null

UNMANAGED_ADAPTER_ROOT="$TMP_ROOT/unmanaged-adapter"
cp -R "$FIXTURE_BASE" "$UNMANAGED_ADAPTER_ROOT"
jq '. + [{"sourceId":"hidden-source","classification":"repo-owned","supportedDestinations":["claude","codex"],"command":"adapters/repo-owned.sh"}]' "$UNMANAGED_ADAPTER_ROOT/scripts/distribution-topology/registry.json" > "$UNMANAGED_ADAPTER_ROOT/registry.tmp"
mv "$UNMANAGED_ADAPTER_ROOT/registry.tmp" "$UNMANAGED_ADAPTER_ROOT/scripts/distribution-topology/registry.json"
run_fixture_json "$UNMANAGED_ADAPTER_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "adapter-without-policy" and .sourceId == "hidden-source")' "$UNMANAGED_ADAPTER_ROOT/result.json" >/dev/null

UNSUPPORTED_ROOT="$TMP_ROOT/unsupported-destination"
cp -R "$FIXTURE_BASE" "$UNSUPPORTED_ROOT"
jq '.[0].supportedDestinations = ["claude"]' "$UNSUPPORTED_ROOT/scripts/distribution-topology/registry.json" > "$UNSUPPORTED_ROOT/registry.tmp"
mv "$UNSUPPORTED_ROOT/registry.tmp" "$UNSUPPORTED_ROOT/scripts/distribution-topology/registry.json"
run_fixture_json "$UNSUPPORTED_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "unsupported-destination" and .sourceId == "repo-claude" and .destination == "codex")' "$UNSUPPORTED_ROOT/result.json" >/dev/null

CODEX_TO_CLAUDE_ROOT="$TMP_ROOT/codex-to-claude"
cp -R "$FIXTURE_BASE" "$CODEX_TO_CLAUDE_ROOT"
jq '.sources[1].overrides["codex-tool"] = ["claude"]' "$CODEX_TO_CLAUDE_ROOT/skill-topology.json" > "$CODEX_TO_CLAUDE_ROOT/manifest.tmp"
mv "$CODEX_TO_CLAUDE_ROOT/manifest.tmp" "$CODEX_TO_CLAUDE_ROOT/skill-topology.json"
run_fixture_json "$CODEX_TO_CLAUDE_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "unsupported-destination" and .sourceId == "repo-codex" and .destination == "claude")' "$CODEX_TO_CLAUDE_ROOT/result.json" >/dev/null

EMPTY_CAPABILITY_ROOT="$TMP_ROOT/empty-unsupported-default"
cp -R "$FIXTURE_BASE" "$EMPTY_CAPABILITY_ROOT"
git -C "$EMPTY_CAPABILITY_ROOT" rm --cached -q codex-skills/codex-tool/SKILL.md
jq '.[1].supportedDestinations = ["claude"]' "$EMPTY_CAPABILITY_ROOT/scripts/distribution-topology/registry.json" > "$EMPTY_CAPABILITY_ROOT/registry.tmp"
mv "$EMPTY_CAPABILITY_ROOT/registry.tmp" "$EMPTY_CAPABILITY_ROOT/scripts/distribution-topology/registry.json"
run_fixture_json "$EMPTY_CAPABILITY_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "unsupported-destination" and .sourceId == "repo-codex" and .destination == "codex")' "$EMPTY_CAPABILITY_ROOT/result.json" >/dev/null

STALE_ROOT="$TMP_ROOT/stale-override"
cp -R "$FIXTURE_BASE" "$STALE_ROOT"
jq '.sources[0].overrides["removed-skill"] = ["codex"]' "$STALE_ROOT/skill-topology.json" > "$STALE_ROOT/manifest.tmp"
mv "$STALE_ROOT/manifest.tmp" "$STALE_ROOT/skill-topology.json"
run_fixture_json "$STALE_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "stale-override" and .skill == "removed-skill")' "$STALE_ROOT/result.json" >/dev/null

set +e
HOME="$STALE_ROOT/home" TMPDIR="$STALE_ROOT/runtime" "$STALE_ROOT/scripts/update-skill-topology.sh" --check > "$STALE_ROOT/human.out" 2> "$STALE_ROOT/human.err"
stale_human_exit=$?
set -e
test "$stale_human_exit" -eq 3
grep -Eq '^repo-claude/removed-skill +- +stale-override +decision-required$' "$STALE_ROOT/human.out"
grep -F 'Result: decision-required (1 decision)' "$STALE_ROOT/human.out" >/dev/null
grep -F 'Decision required:' "$STALE_ROOT/human.err" >/dev/null
grep -F 'override names a skill absent from repo-claude: removed-skill' "$STALE_ROOT/human.err" >/dev/null

PREFLIGHT_ROOT="$TMP_ROOT/reconcile-preflight"
cp -R "$FIXTURE_BASE" "$PREFLIGHT_ROOT"
rm -rf "$PREFLIGHT_ROOT/home/.agents/skills/shared-skill" "$PREFLIGHT_ROOT/home/.agents/skills/codex-tool"
mkdir -p "$PREFLIGHT_ROOT/skills/preflight-hand" "$PREFLIGHT_ROOT/home/.agents/skills/preflight-hand"
printf '%s\n' '---' 'name: preflight-hand' 'description: "fixture"' '---' > "$PREFLIGHT_ROOT/skills/preflight-hand/SKILL.md"
cp "$PREFLIGHT_ROOT/skills/preflight-hand/SKILL.md" "$PREFLIGHT_ROOT/home/.agents/skills/preflight-hand/SKILL.md"
git -C "$PREFLIGHT_ROOT" add skills/preflight-hand/SKILL.md
jq '.sources[0].overrides["removed-skill"] = ["codex"]' "$PREFLIGHT_ROOT/skill-topology.json" > "$PREFLIGHT_ROOT/manifest.tmp"
mv "$PREFLIGHT_ROOT/manifest.tmp" "$PREFLIGHT_ROOT/skill-topology.json"
set +e
HOME="$PREFLIGHT_ROOT/home" TMPDIR="$PREFLIGHT_ROOT/runtime" "$PREFLIGHT_ROOT/scripts/update-skill-topology.sh" --json > "$PREFLIGHT_ROOT/result.json"
preflight_exit=$?
set -e
test "$preflight_exit" -eq 3
jq -e '
  .mode == "reconcile" and .status == "decision-required" and .changes == [] and
  (.skipped[] | .sourceId == "repo-claude" and .skill == "preflight-hand" and .destination == "codex" and .reason == "unowned")
' "$PREFLIGHT_ROOT/result.json" >/dev/null
test ! -e "$PREFLIGHT_ROOT/home/.agents/skills/shared-skill"
test ! -e "$PREFLIGHT_ROOT/home/.agents/skills/codex-tool"

COLLISION_ROOT="$TMP_ROOT/collision"
cp -R "$FIXTURE_BASE" "$COLLISION_ROOT"
mkdir -p "$COLLISION_ROOT/codex-skills/shared-skill"
printf '%s\n' '---' 'name: shared-skill' 'description: "fixture"' '---' > "$COLLISION_ROOT/codex-skills/shared-skill/SKILL.md"
git -C "$COLLISION_ROOT" add codex-skills/shared-skill/SKILL.md
run_fixture_json "$COLLISION_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '
  .status == "decision-required" and
  (.decisions[] | .code == "surface-collision" and .skill == "shared-skill" and .destination == "codex") and
  ([.sources[] | select(.result == "decision-required") | .id] == ["repo-claude", "repo-codex"])
' "$COLLISION_ROOT/result.json" >/dev/null

ADAPTER_FAILURE_ROOT="$TMP_ROOT/adapter-failure"
cp -R "$FIXTURE_BASE" "$ADAPTER_FAILURE_ROOT"
cat > "$ADAPTER_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
echo "fixture discovery failure" >&2
exit 1
BASH
chmod +x "$ADAPTER_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"
run_fixture_json "$ADAPTER_FAILURE_ROOT"
test "$RUN_EXIT" -eq 1
jq -e '.status == "failed" and (.errors[0] | contains("fixture discovery failure"))' "$ADAPTER_FAILURE_ROOT/result.json" >/dev/null
test -z "$(find "$ADAPTER_FAILURE_ROOT/runtime" -mindepth 1 -print -quit)"

RUNTIME_FAILURE_ROOT="$TMP_ROOT/runtime-adapter-failure"
cp -R "$FIXTURE_BASE" "$RUNTIME_FAILURE_ROOT"
rm -rf "$RUNTIME_FAILURE_ROOT/home/.agents/skills/shared-skill" "$RUNTIME_FAILURE_ROOT/home/.agents/skills/codex-tool"
mv "$RUNTIME_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" "$RUNTIME_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$RUNTIME_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${4:-discover}" = reconcile ] || [ "${4:-discover}" = verify ]; then
  printf '%s:%s\n' "$1" "$4" >> "$TOPOLOGY_ADAPTER_LOG"
fi
if [ "$1" = repo-claude ] && [ "${4:-discover}" = reconcile ]; then
  echo "fixture reconcile failure" >&2
  exit 1
fi
exec "${BASH_SOURCE[0]%/*}/repo-owned-real.sh" "$@"
BASH
chmod +x "$RUNTIME_FAILURE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"
set +e
TOPOLOGY_ADAPTER_LOG="$RUNTIME_FAILURE_ROOT/adapter.log" \
HOME="$RUNTIME_FAILURE_ROOT/home" \
TMPDIR="$RUNTIME_FAILURE_ROOT/runtime" \
  "$RUNTIME_FAILURE_ROOT/scripts/update-skill-topology.sh" --json > "$RUNTIME_FAILURE_ROOT/result.json" 2> "$RUNTIME_FAILURE_ROOT/result.err"
runtime_failure_exit=$?
set -e
test "$runtime_failure_exit" -eq 1
test ! -s "$RUNTIME_FAILURE_ROOT/result.err"
test "$(sort "$RUNTIME_FAILURE_ROOT/adapter.log")" = "$(printf '%s\n' repo-claude:reconcile repo-claude:verify repo-codex:reconcile repo-codex:verify | sort)"
test ! -e "$RUNTIME_FAILURE_ROOT/home/.agents/skills/shared-skill"
test -f "$RUNTIME_FAILURE_ROOT/home/.agents/skills/codex-tool/SKILL.md"
jq -e '
  .status == "failed" and
  ([.errors[] | select(contains("source repo-claude reconciliation failed") or contains("source repo-claude verification failed") or contains("final verification failed: repo-claude/shared-skill -> codex: missing"))] | length) == 3 and
  (.changes[] | .sourceId == "repo-codex" and .skill == "codex-tool" and .action == "installed")
' "$RUNTIME_FAILURE_ROOT/result.json" >/dev/null
set +e
TOPOLOGY_ADAPTER_LOG="$RUNTIME_FAILURE_ROOT/adapter.log" \
HOME="$RUNTIME_FAILURE_ROOT/home" \
TMPDIR="$RUNTIME_FAILURE_ROOT/runtime" \
  "$RUNTIME_FAILURE_ROOT/scripts/update-skill-topology.sh" > "$RUNTIME_FAILURE_ROOT/human.out" 2> "$RUNTIME_FAILURE_ROOT/human.err"
runtime_human_exit=$?
set -e
test "$runtime_human_exit" -eq 1
grep -Eq ' +failed$' "$RUNTIME_FAILURE_ROOT/human.out"
grep -F 'Result: failed' "$RUNTIME_FAILURE_ROOT/human.out" >/dev/null
grep -F 'error: source repo-claude reconciliation failed: fixture reconcile failure' "$RUNTIME_FAILURE_ROOT/human.err" >/dev/null
grep -F 'error: source repo-claude verification failed:' "$RUNTIME_FAILURE_ROOT/human.err" >/dev/null
grep -F 'error: final verification failed: repo-claude/shared-skill -> codex: missing' "$RUNTIME_FAILURE_ROOT/human.err" >/dev/null

FINAL_DECISION_ROOT="$TMP_ROOT/final-decision"
cp -R "$FIXTURE_BASE" "$FINAL_DECISION_ROOT"
rm -rf "$FINAL_DECISION_ROOT/home/.agents/skills/shared-skill"
mv "$FINAL_DECISION_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" "$FINAL_DECISION_ROOT/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$FINAL_DECISION_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
real_adapter="${BASH_SOURCE[0]%/*}/repo-owned-real.sh"
if [ "$1" = repo-claude ] && [ "${4:-discover}" = reconcile ]; then
  "$real_adapter" "$@"
  rm -f "$6/.agents/skills/shared-skill/.agent-scripts-copy"
  exit 0
fi
exec "$real_adapter" "$@"
BASH
chmod +x "$FINAL_DECISION_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"
set +e
HOME="$FINAL_DECISION_ROOT/home" TMPDIR="$FINAL_DECISION_ROOT/runtime" \
  "$FINAL_DECISION_ROOT/scripts/update-skill-topology.sh" --json > "$FINAL_DECISION_ROOT/result.json"
final_decision_exit=$?
set -e
test "$final_decision_exit" -eq 3
jq -e '
  .status == "decision-required" and
  (.decisions[] | .code == "surface-ownership-collision" and .sourceId == "repo-claude" and .skill == "shared-skill" and .destination == "codex") and
  (.errors[] | contains("source repo-claude verification failed"))
' "$FINAL_DECISION_ROOT/result.json" >/dev/null

FINAL_SKIP_ROOT="$TMP_ROOT/final-skip"
cp -R "$FIXTURE_BASE" "$FINAL_SKIP_ROOT"
install_repo_copy "$FINAL_SKIP_ROOT/home/.agents/skills/new-skill" "$FINAL_SKIP_ROOT/skills/new-skill" "skills/new-skill"
mv "$FINAL_SKIP_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" "$FINAL_SKIP_ROOT/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$FINAL_SKIP_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
real_adapter="${BASH_SOURCE[0]%/*}/repo-owned-real.sh"
if [ "$1" = repo-claude ] && [ "${4:-discover}" = reconcile ]; then
  marker="$6/.agents/skills/new-skill/.agent-scripts-copy"
  printf '%s\n%s\n%s\n' "$(sed -n '1p' "$marker")" other-owner "$(sed -n '3p' "$marker")" > "$marker"
fi
exec "$real_adapter" "$@"
BASH
chmod +x "$FINAL_SKIP_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"
set +e
HOME="$FINAL_SKIP_ROOT/home" TMPDIR="$FINAL_SKIP_ROOT/runtime" \
  "$FINAL_SKIP_ROOT/scripts/update-skill-topology.sh" --json > "$FINAL_SKIP_ROOT/result.json"
final_skip_exit=$?
set -e
test "$final_skip_exit" -eq 1
jq -e '
  .status == "failed" and
  (.skipped[] | .sourceId == "repo-claude" and .skill == "new-skill" and .destination == "codex" and .reason == "other-owner") and
  (.errors[] | contains("source repo-claude reconciliation failed"))
' "$FINAL_SKIP_ROOT/result.json" >/dev/null

REMOTE_ROOT="$TMP_ROOT/remote-discovery"
cp -R "$FIXTURE_BASE" "$REMOTE_ROOT"
mv "$REMOTE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" "$REMOTE_ROOT/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$REMOTE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$3" >> "$TOPOLOGY_DISCOVERY_LOG"
: > "$3/$1.remote-discovery"
exec "${BASH_SOURCE[0]%/*}/repo-owned-real.sh" "$@"
BASH
chmod +x "$REMOTE_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"
TOPOLOGY_DISCOVERY_LOG="$REMOTE_ROOT/discovery.log" \
HOME="$REMOTE_ROOT/home" \
TMPDIR="$REMOTE_ROOT/runtime" \
  "$REMOTE_ROOT/scripts/update-skill-topology.sh" --check --json > "$REMOTE_ROOT/result.json"
test "$(wc -l < "$REMOTE_ROOT/discovery.log" | tr -d ' ')" -eq 2
while IFS= read -r discovery_path; do
  case "$discovery_path" in
    "$REMOTE_ROOT/runtime"/agent-scripts-topology-discovery-*) ;;
    *) echo "FAIL: discovery escaped temporary storage: $discovery_path" >&2; exit 1 ;;
  esac
  test ! -e "$discovery_path"
done < "$REMOTE_ROOT/discovery.log"

set +e
HOME="$FIXTURE_BASE/home" TMPDIR="$FIXTURE_BASE/runtime" "$FIXTURE_BASE/scripts/update-skill-topology.sh" --check --json --unknown > "$TMP_ROOT/invalid-cli.json" 2> "$TMP_ROOT/invalid-cli.err"
invalid_cli_exit=$?
set -e
test "$invalid_cli_exit" -eq 2
test ! -s "$TMP_ROOT/invalid-cli.err"
jq -e '.status == "invalid" and (.errors[0] | contains("use --check"))' "$TMP_ROOT/invalid-cli.json" >/dev/null

LOCK_ROOT="$TMP_ROOT/lock"
cp -R "$FIXTURE_BASE" "$LOCK_ROOT"
mv "$LOCK_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" "$LOCK_ROOT/scripts/distribution-topology/adapters/repo-owned-real.sh"
cat > "$LOCK_ROOT/scripts/distribution-topology/adapters/repo-owned.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = repo-claude ] && [ -n "${TOPOLOGY_BLOCK_STARTED:-}" ]; then
  : > "$TOPOLOGY_BLOCK_STARTED"
  while [ ! -e "$TOPOLOGY_BLOCK_RELEASE" ]; do
    sleep 0.05
  done
fi

exec "${BASH_SOURCE[0]%/*}/repo-owned-real.sh" "$@"
BASH
chmod +x "$LOCK_ROOT/scripts/distribution-topology/adapters/repo-owned.sh"

TOPOLOGY_BLOCK_STARTED="$LOCK_ROOT/live.started" \
TOPOLOGY_BLOCK_RELEASE="$LOCK_ROOT/live.release" \
HOME="$LOCK_ROOT/home" \
TMPDIR="$LOCK_ROOT/runtime" \
  "$LOCK_ROOT/scripts/update-skill-topology.sh" --check --json > "$LOCK_ROOT/live-first.json" 2> "$LOCK_ROOT/live-first.err" &
live_pid=$!

for _ in {1..100}; do
  [ -e "$LOCK_ROOT/live.started" ] && break
  sleep 0.05
done
test -e "$LOCK_ROOT/live.started"

run_fixture_json "$LOCK_ROOT"
test "$RUN_EXIT" -eq 1
jq -e --arg pid "$live_pid" '.status == "failed" and (.errors[0] | contains("already running") and contains($pid))' "$LOCK_ROOT/result.json" >/dev/null

: > "$LOCK_ROOT/live.release"
wait "$live_pid"
test ! -s "$LOCK_ROOT/live-first.err"

TOPOLOGY_BLOCK_STARTED="$LOCK_ROOT/stale.started" \
TOPOLOGY_BLOCK_RELEASE="$LOCK_ROOT/stale.release" \
HOME="$LOCK_ROOT/home" \
TMPDIR="$LOCK_ROOT/runtime" \
  "$LOCK_ROOT/scripts/update-skill-topology.sh" --check --json > "$LOCK_ROOT/stale-first.json" 2> "$LOCK_ROOT/stale-first.err" &
stale_pid=$!

for _ in {1..100}; do
  [ -e "$LOCK_ROOT/stale.started" ] && break
  sleep 0.05
done
test -e "$LOCK_ROOT/stale.started"
kill -9 "$stale_pid"
: > "$LOCK_ROOT/stale.release"
set +e
wait "$stale_pid" 2>/dev/null
set -e

TOPOLOGY_BLOCK_STARTED="$LOCK_ROOT/recovery-one.started" \
TOPOLOGY_BLOCK_RELEASE="$LOCK_ROOT/recovery.release" \
HOME="$LOCK_ROOT/home" \
TMPDIR="$LOCK_ROOT/runtime" \
  "$LOCK_ROOT/scripts/update-skill-topology.sh" --check --json > "$LOCK_ROOT/recovery-one.json" 2> "$LOCK_ROOT/recovery-one.err" &
recovery_one_pid=$!

TOPOLOGY_BLOCK_STARTED="$LOCK_ROOT/recovery-two.started" \
TOPOLOGY_BLOCK_RELEASE="$LOCK_ROOT/recovery.release" \
HOME="$LOCK_ROOT/home" \
TMPDIR="$LOCK_ROOT/runtime" \
  "$LOCK_ROOT/scripts/update-skill-topology.sh" --check --json > "$LOCK_ROOT/recovery-two.json" 2> "$LOCK_ROOT/recovery-two.err" &
recovery_two_pid=$!

for _ in {1..100}; do
  { [ -e "$LOCK_ROOT/recovery-one.started" ] || [ -e "$LOCK_ROOT/recovery-two.started" ]; } &&
    { [ -s "$LOCK_ROOT/recovery-one.json" ] || [ -s "$LOCK_ROOT/recovery-two.json" ]; } &&
    break
  sleep 0.05
done
test -e "$LOCK_ROOT/recovery-one.started" || test -e "$LOCK_ROOT/recovery-two.started"
test -s "$LOCK_ROOT/recovery-one.json" || test -s "$LOCK_ROOT/recovery-two.json"

: > "$LOCK_ROOT/recovery.release"
set +e
wait "$recovery_one_pid"
recovery_one_exit=$?
wait "$recovery_two_pid"
recovery_two_exit=$?
set -e

if [ "$recovery_one_exit" -eq 0 ] && [ "$recovery_two_exit" -eq 1 ]; then
  recovery_winner="$LOCK_ROOT/recovery-one.json"
  recovery_loser="$LOCK_ROOT/recovery-two.json"
  recovery_winner_pid="$recovery_one_pid"
elif [ "$recovery_one_exit" -eq 1 ] && [ "$recovery_two_exit" -eq 0 ]; then
  recovery_winner="$LOCK_ROOT/recovery-two.json"
  recovery_loser="$LOCK_ROOT/recovery-one.json"
  recovery_winner_pid="$recovery_two_pid"
else
  echo "expected one stale-lock recovery winner, got $recovery_one_exit and $recovery_two_exit" >&2
  exit 1
fi

jq -e --arg pid "$stale_pid" '.status == "clean" and (.warnings[] | .code == "stale-lock-recovered" and (.message | contains($pid)))' "$recovery_winner" >/dev/null
jq -e --arg pid "$recovery_winner_pid" '.status == "failed" and (.errors[0] | contains("already running") and contains($pid))' "$recovery_loser" >/dev/null
test ! -s "$LOCK_ROOT/recovery-one.err"
test ! -s "$LOCK_ROOT/recovery-two.err"
test -z "$(find "$LOCK_ROOT/runtime" -mindepth 1 -print -quit)"

pending_lock="$LOCK_ROOT/runtime/agent-scripts-skill-topology-$(id -u).lock"
mkdir "$pending_lock"
touch -t 202001010000 "$pending_lock"
run_fixture_json "$LOCK_ROOT"
test "$RUN_EXIT" -eq 0
jq -e '.status == "clean" and (.warnings[] | .code == "stale-lock-recovered" and .message == "recovered stale topology lock with no recorded PID")' "$LOCK_ROOT/result.json" >/dev/null
test -z "$(find "$LOCK_ROOT/runtime" -mindepth 1 -print -quit)"

TOPOLOGY_BLOCK_STARTED="$LOCK_ROOT/interrupt.started" \
TOPOLOGY_BLOCK_RELEASE="$LOCK_ROOT/interrupt.release" \
HOME="$LOCK_ROOT/home" \
TMPDIR="$LOCK_ROOT/runtime" \
  "$LOCK_ROOT/scripts/update-skill-topology.sh" --check --json > "$LOCK_ROOT/interrupt.json" 2> "$LOCK_ROOT/interrupt.err" &
interrupt_pid=$!

for _ in {1..100}; do
  [ -e "$LOCK_ROOT/interrupt.started" ] && break
  sleep 0.05
done
test -e "$LOCK_ROOT/interrupt.started"
kill -INT "$interrupt_pid"
: > "$LOCK_ROOT/interrupt.release"
set +e
wait "$interrupt_pid"
interrupt_exit=$?
set -e

test "$interrupt_exit" -eq 130
test ! -s "$LOCK_ROOT/interrupt.err"
jq -e '.status == "interrupted" and .errors == ["interrupted"]' "$LOCK_ROOT/interrupt.json" >/dev/null
test -z "$(find "$LOCK_ROOT/runtime" -mindepth 1 -print -quit)"
run_fixture_json "$LOCK_ROOT"
test "$RUN_EXIT" -eq 0
jq -e '.status == "clean" and .warnings == []' "$LOCK_ROOT/result.json" >/dev/null

echo "update-skill-topology tests passed"
