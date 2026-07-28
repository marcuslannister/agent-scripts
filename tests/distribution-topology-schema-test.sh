#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
SCHEMA_DIR="$REPO_ROOT/agent-tooling/distribution-topology"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

source "$SCHEMA_DIR/errors.sh"
source "$SCHEMA_DIR/schema.sh"

JQ_REAL="$(command -v jq)"
JQ_COUNT_FILE="$FIXTURE/jq-count"
export JQ_REAL JQ_COUNT_FILE
mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/jq" <<'SHIM'
#!/usr/bin/env bash
count=0
[ ! -f "$JQ_COUNT_FILE" ] || IFS= read -r count < "$JQ_COUNT_FILE"
printf '%s\n' "$((count + 1))" > "$JQ_COUNT_FILE"
exec "$JQ_REAL" "$@"
SHIM
chmod +x "$FIXTURE/bin/jq"
PATH="$FIXTURE/bin:$PATH"
export PATH

fail() {
  printf 'distribution topology schema: %s\n' "$1" >&2
  exit 1
}

reset_count() {
  printf '0\n' > "$JQ_COUNT_FILE"
}

assert_one_jq() {
  local label="$1" count
  IFS= read -r count < "$JQ_COUNT_FILE"
  [ "$count" = 1 ] || fail "$label used $count jq invocations (expected 1)"
}

expect_valid() {
  local label="$1" validator="$2" file="$3"
  reset_count
  TOPOLOGY_ERROR_CODE=1
  TOPOLOGY_ERROR_MESSAGE=
  "$validator" "$file" || fail "$label rejected valid input: $TOPOLOGY_ERROR_MESSAGE"
  assert_one_jq "$label"
}

expect_error() {
  local label="$1" validator="$2" file="$3" expected="$4" result=0
  reset_count
  TOPOLOGY_ERROR_CODE=1
  TOPOLOGY_ERROR_MESSAGE=
  "$validator" "$file" || result=$?
  [ "$result" = 2 ] || fail "$label exited $result (expected 2)"
  [ "$TOPOLOGY_ERROR_MESSAGE" = "$expected" ] \
    || fail "$label message changed: $TOPOLOGY_ERROR_MESSAGE"
  assert_one_jq "$label"
}

case_number=0
expect_mutation_error() {
  local label="$1" validator="$2" input="$3" filter="$4" expected="$5" file
  file="$FIXTURE/case-$case_number.json"
  case_number=$((case_number + 1))
  "$JQ_REAL" "$filter" "$input" > "$file"
  expect_error "$label" "$validator" "$file" "$expected"
}

expect_parse_error() {
  local label="$1" validator="$2" file="$3" parse_label="$4" expected result=0
  expected="$($JQ_REAL empty "$file" 2>&1 || true)"
  expected="$parse_label is not valid JSON: $expected"
  reset_count
  TOPOLOGY_ERROR_CODE=1
  TOPOLOGY_ERROR_MESSAGE=
  "$validator" "$file" || result=$?
  [ "$result" = 2 ] || fail "$label exited $result (expected 2)"
  [ "$TOPOLOGY_ERROR_MESSAGE" = "$expected" ] \
    || fail "$label message changed: $TOPOLOGY_ERROR_MESSAGE"
  assert_one_jq "$label"
}

manifest="$REPO_ROOT/agent-tooling/skill-topology.json"
registry="$SCHEMA_DIR/registry.json"
expect_valid 'manifest validation' topology_validate_manifest "$manifest"
expect_valid 'registry validation' topology_validate_registry "$registry"

printf '{' > "$FIXTURE/invalid.json"
expect_parse_error 'manifest parse error' topology_validate_manifest "$FIXTURE/invalid.json" \
  'skill topology manifest'
expect_parse_error 'registry parse error' topology_validate_registry "$FIXTURE/invalid.json" \
  'topology adapter registry'

expect_mutation_error 'manifest root type' topology_validate_manifest "$manifest" '[]' \
  'skill topology manifest must be an object'
expect_mutation_error 'manifest unknown field' topology_validate_manifest "$manifest" \
  '. + {unexpected: true}' 'skill topology manifest contains unknown field: unexpected'
expect_mutation_error 'manifest missing version' topology_validate_manifest "$manifest" \
  'del(.version)' 'skill topology manifest is missing required field: version'
expect_mutation_error 'manifest version' topology_validate_manifest "$manifest" \
  '.version = 2' 'skill topology manifest version must be 1'
expect_mutation_error 'manifest sources' topology_validate_manifest "$manifest" \
  '.sources = []' 'skill topology manifest sources must be a non-empty array'
expect_mutation_error 'manifest duplicate source' topology_validate_manifest "$manifest" \
  '.sources += [.sources[0]]' 'skill topology manifest contains duplicate source id: repo-claude'
expect_mutation_error 'manifest structured duplicate source' topology_validate_manifest "$manifest" \
  '.sources[0].id = {x: 1} | .sources[1].id = {x: 1}' \
  'skill topology manifest contains duplicate source id: {'
expect_mutation_error 'manifest duplicate precedes entry type' topology_validate_manifest "$manifest" \
  '.sources[1] = null | .sources += [.sources[0]]' \
  'skill topology manifest contains duplicate source id: repo-claude'
expect_mutation_error 'manifest source type' topology_validate_manifest "$manifest" \
  '.sources[0] = null' 'skill topology manifest source 0 must be an object'
expect_mutation_error 'manifest source scalar type' topology_validate_manifest "$manifest" \
  '.sources[0] = "scalar"' 'skill topology manifest source 0 must be an object'
expect_mutation_error 'manifest entry order before later type' topology_validate_manifest "$manifest" \
  '.sources[0].id = "Bad" | .sources[1] = null' \
  'skill topology manifest source 0 has an invalid id'
expect_mutation_error 'manifest scalar entries are not duplicate ids' topology_validate_manifest "$manifest" \
  '.sources[0] = "first" | .sources[1] = "second"' \
  'skill topology manifest source 0 must be an object'
expect_mutation_error 'manifest source unknown field' topology_validate_manifest "$manifest" \
  '.sources[0].unexpected = true' 'skill topology manifest source 0 contains unknown field: unexpected'
expect_mutation_error 'manifest missing source id' topology_validate_manifest "$manifest" \
  'del(.sources[0].id)' 'skill topology manifest source 0 is missing required field: id'
expect_mutation_error 'manifest invalid source id' topology_validate_manifest "$manifest" \
  '.sources[0].id = "Bad"' 'skill topology manifest source 0 has an invalid id'
expect_mutation_error 'manifest classification' topology_validate_manifest "$manifest" \
  '.sources[0].classification = "bad"' 'skill topology manifest source 0 contains unknown classification: bad'
expect_mutation_error 'manifest structured classification' topology_validate_manifest "$manifest" \
  '.sources[0].classification = {x: 1}' \
  $'skill topology manifest source 0 contains unknown classification: {\n  "x": 1\n}'
expect_mutation_error 'manifest destination type' topology_validate_manifest "$manifest" \
  '.sources[0].defaultDestinations = {}' \
  'skill topology manifest source 0 defaultDestinations must be a non-empty destination array'
expect_mutation_error 'manifest destinations empty' topology_validate_manifest "$manifest" \
  '.sources[0].defaultDestinations = []' \
  'skill topology manifest source 0 defaultDestinations must be a non-empty destination array'
expect_mutation_error 'manifest destination unknown' topology_validate_manifest "$manifest" \
  '.sources[0].defaultDestinations = ["unknown"]' \
  'skill topology manifest source 0 defaultDestinations contains unknown destination: unknown'
expect_mutation_error 'manifest destination duplicate' topology_validate_manifest "$manifest" \
  '.sources[0].defaultDestinations = ["claude", "claude"]' \
  'skill topology manifest source 0 defaultDestinations contains a duplicate destination'

expect_mutation_error 'registry root type' topology_validate_registry "$registry" '{}' \
  'topology adapter registry must be a non-empty array'
expect_mutation_error 'registry empty' topology_validate_registry "$registry" '[]' \
  'topology adapter registry must be a non-empty array'
expect_mutation_error 'registry duplicate source' topology_validate_registry "$registry" \
  '. += [.[0]]' 'topology adapter registry contains duplicate sourceId: matt-skills'
expect_mutation_error 'registry structured duplicate source' topology_validate_registry "$registry" \
  '.[0].sourceId = {x: 1} | .[1].sourceId = {x: 1}' \
  'topology adapter registry contains duplicate sourceId: {'
expect_mutation_error 'registry duplicate precedes entry type' topology_validate_registry "$registry" \
  '.[1] = null | . += [.[0]]' \
  'topology adapter registry contains duplicate sourceId: matt-skills'
expect_mutation_error 'registry entry type' topology_validate_registry "$registry" \
  '.[0] = null' 'topology adapter registry entry 0 must be an object'
expect_mutation_error 'registry entry scalar type' topology_validate_registry "$registry" \
  '.[0] = 42' 'topology adapter registry entry 0 must be an object'
expect_mutation_error 'registry entry order before later type' topology_validate_registry "$registry" \
  '.[0].command = "" | .[1] = null' \
  'topology adapter registry entry 0 has an invalid command'
expect_mutation_error 'registry scalar entries are not duplicate ids' topology_validate_registry "$registry" \
  '.[0] = "first" | .[1] = 42' \
  'topology adapter registry entry 0 must be an object'
expect_mutation_error 'registry unknown field' topology_validate_registry "$registry" \
  '.[0].unexpected = true' 'topology adapter registry entry 0 contains unknown field: unexpected'
expect_mutation_error 'registry missing command' topology_validate_registry "$registry" \
  'del(.[0].command)' 'topology adapter registry entry 0 is missing required field: command'
expect_mutation_error 'registry source id' topology_validate_registry "$registry" \
  '.[0].sourceId = "Bad"' 'topology adapter registry entry 0 has an invalid sourceId'
expect_mutation_error 'registry classification' topology_validate_registry "$registry" \
  '.[0].classification = "bad"' 'topology adapter registry entry 0 contains unknown classification: bad'
expect_mutation_error 'registry structured classification' topology_validate_registry "$registry" \
  '.[0].classification = {x: 1}' \
  $'topology adapter registry entry 0 contains unknown classification: {\n  "x": 1\n}'
expect_mutation_error 'registry destination type' topology_validate_registry "$registry" \
  '.[0].supportedDestinations = {}' \
  'topology adapter registry entry 0 supportedDestinations must be a non-empty destination array'
expect_mutation_error 'registry destinations empty' topology_validate_registry "$registry" \
  '.[0].supportedDestinations = []' \
  'topology adapter registry entry 0 supportedDestinations must be a non-empty destination array'
expect_mutation_error 'registry destination unknown' topology_validate_registry "$registry" \
  '.[0].supportedDestinations = ["unknown"]' \
  'topology adapter registry entry 0 supportedDestinations contains unknown destination: unknown'
expect_mutation_error 'registry destination duplicate' topology_validate_registry "$registry" \
  '.[0].supportedDestinations = ["codex", "codex"]' \
  'topology adapter registry entry 0 supportedDestinations contains a duplicate destination'
expect_mutation_error 'registry command empty' topology_validate_registry "$registry" \
  '.[0].command = ""' 'topology adapter registry entry 0 has an invalid command'
expect_mutation_error 'registry command traversal' topology_validate_registry "$registry" \
  '.[0].command = "dir\\\\..\\\\outside.sh"' 'topology adapter registry entry 0 has an invalid command'
expect_mutation_error 'registry state inspection' topology_validate_registry "$registry" \
  '.[0].stateInspection = "bad"' 'topology adapter registry entry 0 has an invalid stateInspection'
expect_mutation_error 'registry matrix source' topology_validate_registry "$registry" \
  '.[0].matrixSource = "bad"' 'topology adapter registry entry 0 has an invalid matrixSource'
expect_mutation_error 'registry non-plugin metadata' topology_validate_registry "$registry" \
  '.[0].plugin = {}' 'topology adapter registry entry 0 has plugin metadata for a non-plugin source'
expect_mutation_error 'registry missing plugin' topology_validate_registry "$registry" \
  'del(.[2].plugin)' 'topology adapter registry entry 2 requires plugin metadata for a plugin source'
expect_mutation_error 'plugin unknown field' topology_validate_registry "$registry" \
  '.[2].plugin.unexpected = true' 'topology adapter registry entry 2 plugin contains unknown field: unexpected'
expect_mutation_error 'plugin missing name' topology_validate_registry "$registry" \
  'del(.[2].plugin.name)' 'topology adapter registry entry 2 plugin is missing required field: name'
expect_mutation_error 'plugin name' topology_validate_registry "$registry" \
  '.[2].plugin.name = "Bad"' 'topology adapter registry entry 2 plugin has an invalid name'
expect_mutation_error 'plugin repo' topology_validate_registry "$registry" \
  '.[2].plugin.repo = "bad"' 'topology adapter registry entry 2 plugin has an invalid repo'
expect_mutation_error 'plugin marketplaces empty' topology_validate_registry "$registry" \
  '.[2].plugin.marketplaces = {}' 'topology adapter registry entry 2 plugin marketplaces must be a non-empty object'
expect_mutation_error 'plugin marketplace unknown' topology_validate_registry "$registry" \
  '.[2].plugin.marketplaces.bad = "bad"' \
  'topology adapter registry entry 2 plugin marketplaces contains unknown destination: bad'
expect_mutation_error 'plugin marketplace unsupported' topology_validate_registry "$registry" \
  '.[2].plugin.marketplaces.codex = "codex"' \
  'topology adapter registry entry 2 plugin marketplaces contains unsupported destination: codex'
expect_mutation_error 'plugin marketplace key order' topology_validate_registry "$registry" \
  '.[2].plugin.marketplaces = {codex: "codex", zbad: "bad"}' \
  'topology adapter registry entry 2 plugin marketplaces contains unsupported destination: codex'
expect_mutation_error 'plugin identifiers empty' topology_validate_registry "$registry" \
  '.[2].plugin.identifiers = {}' 'topology adapter registry entry 2 plugin identifiers must be a non-empty object'
expect_mutation_error 'plugin identifier unknown' topology_validate_registry "$registry" \
  '.[2].plugin.identifiers = {bad: "bad"}' \
  'topology adapter registry entry 2 plugin identifiers contains unknown destination: bad'
expect_mutation_error 'plugin identifier invalid' topology_validate_registry "$registry" \
  '.[2].plugin.identifiers = {claude: "Bad"}' \
  'topology adapter registry entry 2 plugin has an invalid native claude identifier'
expect_mutation_error 'plugin identifier key order' topology_validate_registry "$registry" \
  '.[2].plugin.identifiers = {claude: "Bad", zbad: "bad"}' \
  'topology adapter registry entry 2 plugin has an invalid native claude identifier'
expect_mutation_error 'plugin marketplace invalid' topology_validate_registry "$registry" \
  '.[2].plugin.marketplaces.claude = "Bad"' \
  'topology adapter registry entry 2 plugin is missing a valid claude marketplace'
expect_mutation_error 'dual plugin marketplace missing' topology_validate_registry "$registry" \
  'del(.[7].plugin.marketplaces.codex)' \
  'topology adapter registry entry 7 plugin is missing a valid codex marketplace'
expect_mutation_error 'plugin skills empty' topology_validate_registry "$registry" \
  '.[2].plugin.skills = []' 'topology adapter registry entry 2 plugin skills must be a non-empty array'
expect_mutation_error 'plugin skill duplicate' topology_validate_registry "$registry" \
  '.[2].plugin.skills = ["same", "same"]' \
  'topology adapter registry entry 2 plugin skills contains a duplicate skill'
expect_mutation_error 'plugin skill invalid' topology_validate_registry "$registry" \
  '.[2].plugin.skills = ["Bad"]' \
  'topology adapter registry entry 2 plugin skills contains an invalid skill name: Bad'

printf 'distribution topology schema tests passed (%s diagnostic cases)\n' "$case_number"
