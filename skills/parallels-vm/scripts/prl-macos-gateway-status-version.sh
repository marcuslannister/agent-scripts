#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-macos-lib.sh
source "$SCRIPT_DIR/prl-macos-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--profile <name>] [--state-dir <dir>] [--timeout <ms>] [--json]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

profile=
state_dir=
timeout_ms=
json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile=${2:?missing profile}
      shift 2
      ;;
    --state-dir)
      state_dir=${2:?missing state dir}
      shift 2
      ;;
    --timeout)
      timeout_ms=${2:?missing timeout}
      shift 2
      ;;
    --json)
      json_mode=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

env_args=()
[[ -n "$profile" ]] && env_args+=("OPENCLAW_PROFILE=$profile")
[[ -n "$state_dir" ]] && env_args+=("OPENCLAW_STATE_DIR=$state_dir")

cmd=("$SCRIPT_DIR/prl-macos-openclaw.sh" "$vm")
for env_arg in "${env_args[@]}"; do
  cmd+=(--env "$env_arg")
done
cmd+=(gateway status --json)
if [[ -n "$timeout_ms" ]]; then
  cmd+=(--timeout "$timeout_ms")
fi

raw="$("${cmd[@]}" 2>&1)"

summary="$(printf '%s\n' "$raw" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8");
const lines = input.split(/\r?\n/);
const start = lines.findIndex((line) => line.trim().startsWith("{"));
if (start < 0) {
  process.stderr.write(input);
  process.exit(1);
}
const parsed = JSON.parse(lines.slice(start).join("\n"));
const listener = Array.isArray(parsed.port?.listeners) ? parsed.port.listeners[0] ?? null : null;
const out = {
  runtimeVersion: parsed.runtimeVersion ?? null,
  rpcOk: parsed.rpc?.ok === true,
  servicePid: parsed.service?.runtime?.pid ?? null,
  listenerPid: listener?.pid ?? null,
  port: parsed.gateway?.port ?? null,
  raw: parsed,
};
process.stdout.write(JSON.stringify(out));
')"

if [[ "$json_mode" == "1" ]]; then
  printf '%s\n' "$summary" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const parsed = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(parsed, null, 2) + "\n");
'
  exit 0
fi

printf '%s\n' "$summary" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const parsed = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(`runtimeVersion=${parsed.runtimeVersion ?? ""}`);
console.log(`rpcOk=${parsed.rpcOk}`);
console.log(`servicePid=${parsed.servicePid ?? ""}`);
console.log(`listenerPid=${parsed.listenerPid ?? ""}`);
console.log(`port=${parsed.port ?? ""}`);
'
