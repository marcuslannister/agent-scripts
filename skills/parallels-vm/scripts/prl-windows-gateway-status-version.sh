#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--json]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_mode=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

set +e
raw="$("$SCRIPT_DIR/prl-windows-openclaw.sh" "$vm" gateway status --json 2>&1)"
status=$?
set -e

summary="$(printf '%s\n' "$raw" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8");
const exitCode = Number(process.argv[1]);
const lines = input.split(/\r?\n/);
const start = lines.findIndex((line) => line.trim().startsWith("{"));
if (start >= 0) {
  const parsed = JSON.parse(lines.slice(start).join("\n"));
  const listener = Array.isArray(parsed.port?.listeners) ? parsed.port.listeners[0] ?? null : null;
  process.stdout.write(JSON.stringify({
    runtimeVersion: parsed.runtimeVersion ?? null,
    rpcOk: parsed.rpc?.ok === true,
    servicePid: parsed.service?.runtime?.pid ?? null,
    listenerPid: listener?.pid ?? null,
    port: parsed.gateway?.port ?? null,
    error: null,
    exitCode,
    raw: parsed,
  }));
  process.exit(0);
}
process.stdout.write(JSON.stringify({
  runtimeVersion: null,
  rpcOk: false,
  servicePid: null,
  listenerPid: null,
  port: null,
  error: input.trim() || `command exited with ${exitCode}`,
  exitCode,
  raw: null,
}));
' "$status")"

if [[ "$json_mode" == "1" ]]; then
  printf '%s\n' "$summary" | /opt/homebrew/bin/node -e '
const fs = require("fs");
process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync(0, "utf8")), null, 2) + "\n");
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
if (parsed.error) {
  console.log(`error=${parsed.error}`);
}
'
