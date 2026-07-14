#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND="$REPO_ROOT/scripts/update-skill-topology.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

help_output="$($COMMAND --help)"
grep -F 'Usage: update-skill-topology.sh --check [--json]' <<< "$help_output" >/dev/null
grep -F '0   check clean' <<< "$help_output" >/dev/null
grep -F '1   drift or verification failure' <<< "$help_output" >/dev/null
grep -F '2   invalid usage or manifest' <<< "$help_output" >/dev/null
grep -F '3   user decision required' <<< "$help_output" >/dev/null
grep -F '130 interrupted' <<< "$help_output" >/dev/null

HOME_DIR="$TMP_ROOT/home"
RUNTIME_DIR="$TMP_ROOT/runtime"
mkdir -p "$HOME_DIR/.agents/skills" "$RUNTIME_DIR"

CODEX_EXCEPTIONS=(
  create-cli
  github-author-context
  github-cache-hygiene
  github-deep-review
  github-project-triage
  mac-maintenance
  markdown-converter
  nano-banana-pro
  native-app-performance
  obsidian
  onecli-gateway
  openai-image-gen
  peekaboo
  release-mac-app
  reminders
  remote-mac
  review-claudemd
  skill-cleaner
  ssh-doctor
  validate-skills
  video-transcript-downloader
)

for skill in "${CODEX_EXCEPTIONS[@]}"; do
  mkdir -p "$HOME_DIR/.agents/skills/$skill"
done

HOME="$HOME_DIR" TMPDIR="$RUNTIME_DIR" "$COMMAND" --check --json > "$TMP_ROOT/clean.json" 2> "$TMP_ROOT/clean.err"
test ! -s "$TMP_ROOT/clean.err"
jq -e '
  .schemaVersion == 1 and
  .mode == "check" and
  .status == "clean" and
  .drift == [] and
  .decisions == [] and
  .errors == [] and
  ([.sources[].id] == ["repo-claude", "repo-codex"]) and
  (.plan[] | select(.skill == "codex-first") | .destinations == ["claude"]) and
  (.plan[] | select(.skill == "create-cli") | .destinations == ["claude", "codex"])
' "$TMP_ROOT/clean.json" >/dev/null
jq -e '.sources[] | select(.id == "repo-claude") | (.overrides | has("codex-first") | not)' "$REPO_ROOT/skill-topology.json" >/dev/null

DRIFT_HOME="$TMP_ROOT/drift-home"
DRIFT_RUNTIME="$TMP_ROOT/drift-runtime"
mkdir -p \
  "$DRIFT_HOME/.agents/skills/codex-first" \
  "$DRIFT_HOME/.cache/topology-source" \
  "$DRIFT_HOME/.claude/plugins" \
  "$DRIFT_HOME/.codex/plugins" \
  "$DRIFT_RUNTIME"
printf 'cache sentinel\n' > "$DRIFT_HOME/.cache/topology-source/state"
printf 'claude plugin sentinel\n' > "$DRIFT_HOME/.claude/plugins/state"
printf 'codex plugin sentinel\n' > "$DRIFT_HOME/.codex/plugins/state"

for skill in "${CODEX_EXCEPTIONS[@]}"; do
  [ "$skill" = create-cli ] || mkdir -p "$DRIFT_HOME/.agents/skills/$skill"
done

cp -R "$DRIFT_HOME" "$TMP_ROOT/drift-home-before"
manifest_before="$(cksum "$REPO_ROOT/skill-topology.json")"

set +e
HOME="$DRIFT_HOME" TMPDIR="$DRIFT_RUNTIME" "$COMMAND" --check > "$TMP_ROOT/drift.out" 2> "$TMP_ROOT/drift.err"
drift_exit=$?
set -e

test "$drift_exit" -eq 1
test ! -s "$TMP_ROOT/drift.err"
grep -F 'SOURCE       INVENTORY  DEFAULT  RESULT' "$TMP_ROOT/drift.out" >/dev/null
grep -F 'repo-claude/create-cli -> codex: missing' "$TMP_ROOT/drift.out" >/dev/null
grep -F 'repo-claude/codex-first -> codex: unexpected' "$TMP_ROOT/drift.out" >/dev/null
grep -F 'Result: drift (2 changes)' "$TMP_ROOT/drift.out" >/dev/null
diff -r "$TMP_ROOT/drift-home-before" "$DRIFT_HOME"
test "$manifest_before" = "$(cksum "$REPO_ROOT/skill-topology.json")"
test -z "$(find "$DRIFT_RUNTIME" -mindepth 1 -print -quit)"

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
  cp "$COMMAND" "$fixture_root/scripts/"
  cp -R "$REPO_ROOT/scripts/distribution-topology" "$fixture_root/scripts/"
  printf '%s\n' '---' 'name: new-skill' 'description: "fixture"' '---' > "$fixture_root/skills/new-skill/SKILL.md"
  printf '%s\n' '---' 'name: shared-skill' 'description: "fixture"' '---' > "$fixture_root/skills/shared-skill/SKILL.md"
  printf '%s\n' '---' 'name: codex-tool' 'description: "fixture"' '---' > "$fixture_root/codex-skills/codex-tool/SKILL.md"
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
}

FIXTURE_BASE="$TMP_ROOT/fixture-base"
make_fixture "$FIXTURE_BASE"
HOME="$FIXTURE_BASE/home" TMPDIR="$FIXTURE_BASE/runtime" "$FIXTURE_BASE/scripts/update-skill-topology.sh" --check --json > "$TMP_ROOT/fixture-clean.json"
jq -e '
  .status == "clean" and
  (.plan[] | select(.skill == "new-skill") | .destinations == ["claude"]) and
  (.plan[] | select(.skill == "shared-skill") | .destinations == ["claude", "codex"]) and
  (.plan[] | select(.skill == "codex-tool") | .destinations == ["codex"])
' "$TMP_ROOT/fixture-clean.json" >/dev/null

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

MISSING_ADAPTER_ROOT="$TMP_ROOT/missing-adapter"
cp -R "$FIXTURE_BASE" "$MISSING_ADAPTER_ROOT"
jq '.sources[0].id = "manifest-only"' "$MISSING_ADAPTER_ROOT/skill-topology.json" > "$MISSING_ADAPTER_ROOT/manifest.tmp"
mv "$MISSING_ADAPTER_ROOT/manifest.tmp" "$MISSING_ADAPTER_ROOT/skill-topology.json"
run_fixture_json "$MISSING_ADAPTER_ROOT"
test "$RUN_EXIT" -eq 2
jq -e '.status == "invalid" and (.errors[0] | contains("no registered adapter"))' "$MISSING_ADAPTER_ROOT/result.json" >/dev/null

CLASSIFICATION_ROOT="$TMP_ROOT/classification-mismatch"
cp -R "$FIXTURE_BASE" "$CLASSIFICATION_ROOT"
jq '.[0].classification = "plugin-both"' "$CLASSIFICATION_ROOT/scripts/distribution-topology/registry.json" > "$CLASSIFICATION_ROOT/registry.tmp"
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
grep -F 'repo-claude  2          claude   decision-required' "$STALE_ROOT/human.out" >/dev/null
grep -F 'Result: decision-required (1 decision)' "$STALE_ROOT/human.out" >/dev/null
grep -F 'Decision required:' "$STALE_ROOT/human.err" >/dev/null
grep -F 'override names a skill absent from repo-claude: removed-skill' "$STALE_ROOT/human.err" >/dev/null

COLLISION_ROOT="$TMP_ROOT/collision"
cp -R "$FIXTURE_BASE" "$COLLISION_ROOT"
mkdir -p "$COLLISION_ROOT/codex-skills/shared-skill"
printf '%s\n' '---' 'name: shared-skill' 'description: "fixture"' '---' > "$COLLISION_ROOT/codex-skills/shared-skill/SKILL.md"
run_fixture_json "$COLLISION_ROOT"
test "$RUN_EXIT" -eq 3
jq -e '.status == "decision-required" and (.decisions[] | .code == "surface-collision" and .skill == "shared-skill" and .destination == "codex")' "$COLLISION_ROOT/result.json" >/dev/null

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

run_fixture_json "$LOCK_ROOT"
test "$RUN_EXIT" -eq 0
jq -e --arg pid "$stale_pid" '.status == "clean" and (.warnings[] | .code == "stale-lock-recovered" and (.message | contains($pid)))' "$LOCK_ROOT/result.json" >/dev/null
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
