#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-macos-lib.sh
source "$SCRIPT_DIR/prl-macos-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--agent <agent-id>] [--guest-path <path>] [--provider <provider:ENV_VAR> ...]" >&2
  echo "default providers: openai:OPENAI_API_KEY anthropic:ANTHROPIC_API_KEY" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

agent_id=main
guest_path=
provider_specs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      agent_id=${2:?missing agent id}
      shift 2
      ;;
    --guest-path)
      guest_path=${2:?missing guest path}
      shift 2
      ;;
    --provider)
      provider_specs+=("${2:?missing provider:ENV_VAR}")
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ ${#provider_specs[@]} -eq 0 ]]; then
  provider_specs=(
    "openai:OPENAI_API_KEY"
    "anthropic:ANTHROPIC_API_KEY"
  )
fi

tmp_json=$(mktemp)
trap 'rm -f "$tmp_json"' EXIT

json_lines=()
for spec in "${provider_specs[@]}"; do
  provider=${spec%%:*}
  env_var=${spec#*:}
  [[ -n "$provider" && -n "$env_var" && "$provider" != "$env_var" ]] ||
    prl_die "invalid provider spec: $spec (expected provider:ENV_VAR)"
  value=${!env_var-}
  [[ -n "$value" ]] || prl_die "host env var missing: $env_var"
  json_lines+=("$provider" "$env_var" "$value")
done

/opt/homebrew/bin/node - "$tmp_json" "${json_lines[@]}" <<'NODE'
const fs = require("node:fs");

const [, , outPath, ...triples] = process.argv;
if (!outPath || triples.length === 0 || triples.length % 3 !== 0) {
  throw new Error("invalid args");
}

const profiles = {};
const order = {};

for (let i = 0; i < triples.length; i += 3) {
  const provider = triples[i];
  const envVar = triples[i + 1];
  const key = triples[i + 2];
  const profileId = `${provider}:default`;
  profiles[profileId] = {
    type: "api_key",
    provider,
    key,
  };
  order[provider] = [profileId];
  if (!key) {
    throw new Error(`missing key for ${provider} (${envVar})`);
  }
}

fs.writeFileSync(
  outPath,
  JSON.stringify(
    {
      version: 1,
      profiles,
      order,
    },
    null,
    2,
  ),
);
NODE

seed_args=("$vm" "$tmp_json" --agent "$agent_id")
if [[ -n "$guest_path" ]]; then
  seed_args+=(--guest-path "$guest_path")
fi

"$SCRIPT_DIR/prl-macos-auth-seed.sh" "${seed_args[@]}"
