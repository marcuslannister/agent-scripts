#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--openai-api-key-env <env-var>] [--openai-api-key <key>] [--install-daemon] [--workspace <path>] [--hatch] [--hatch-message <text>] [--hatch-expect <text>] [--json]" >&2
  exit "${1:-64}"
}

[[ $# -ge 1 ]] || usage

case "${1:-}" in
  -h|--help)
    usage 0
    ;;
esac

vm=$1
shift

openai_api_key=
openai_api_key_env=
install_daemon=0
workspace=
hatch=0
hatch_message="Reply with exactly WINDOWS-HATCH-OK."
hatch_expect="WINDOWS-HATCH-OK"
json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openai-api-key-env)
      openai_api_key_env=${2:?missing env var}
      shift 2
      ;;
    --openai-api-key)
      openai_api_key=${2:?missing key}
      shift 2
      ;;
    --install-daemon)
      install_daemon=1
      shift
      ;;
    --workspace)
      workspace=${2:?missing workspace}
      shift 2
      ;;
    --hatch)
      hatch=1
      shift
      ;;
    --hatch-message)
      hatch_message=${2:?missing hatch message}
      shift 2
      ;;
    --hatch-expect)
      hatch_expect=${2:?missing hatch expect}
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

if [[ -n "$openai_api_key" && -n "$openai_api_key_env" ]]; then
  prl_windows_die "pass only one of --openai-api-key or --openai-api-key-env"
fi

env_args=()
auth_choice=skip
if [[ -n "$openai_api_key_env" ]]; then
  [[ -n "${!openai_api_key_env:-}" ]] || prl_windows_die "host env var $openai_api_key_env is empty"
  env_args+=("OPENAI_API_KEY=${!openai_api_key_env}")
  auth_choice=openai-api-key
elif [[ -n "$openai_api_key" ]]; then
  env_args+=("OPENAI_API_KEY=$openai_api_key")
  auth_choice=openai-api-key
fi

if [[ "$hatch" == "1" && "$auth_choice" == "skip" ]]; then
  prl_windows_die "--hatch requires --openai-api-key-env or --openai-api-key"
fi

cmd=(onboard --non-interactive --mode local --auth-choice "$auth_choice" --skip-skills --accept-risk --json)
if [[ "$install_daemon" == "1" ]]; then
  cmd+=(--install-daemon)
fi
if [[ -n "$workspace" ]]; then
  cmd+=(--workspace "$workspace")
fi

wrapper_args=()
for env_arg in "${env_args[@]}"; do
  wrapper_args+=(--env "$env_arg")
done

prl_windows_wait_for_user_session "$vm"

set +e
raw="$("$SCRIPT_DIR/prl-windows-openclaw.sh" "$vm" "${wrapper_args[@]}" "${cmd[@]}" 2>&1)"
status=$?
set -e

json_raw=
if json_raw=$(printf '%s\n' "$raw" | prl_windows_extract_json 2>/dev/null); then
  :
else
  json_raw=
fi
raw_b64=$(printf '%s' "$raw" | /usr/bin/base64)

hatch_json='{"attempted":false,"ok":false,"matched":false,"error":null,"output":null,"expected":null}'
if [[ "$hatch" == "1" ]]; then
  set +e
  hatch_raw="$("$SCRIPT_DIR/prl-windows-openclaw.sh" "$vm" "${wrapper_args[@]}" agent --local --agent main --json --thinking low -m "$hatch_message" 2>&1)"
  hatch_status=$?
  set -e
  hatch_raw_b64=$(printf '%s' "$hatch_raw" | /usr/bin/base64)
  hatch_json="$(/opt/homebrew/bin/node -e '
const raw = Buffer.from(process.argv[1], "base64").toString("utf8");
const exitCode = Number(process.argv[2]);
const expected = process.argv[3];
process.stdout.write(JSON.stringify({
  attempted: true,
  ok: exitCode === 0,
  matched: raw.includes(expected),
  error: exitCode === 0 ? null : raw.trim() || `command exited with ${exitCode}`,
  output: raw.trim() || null,
  expected,
}));
' "$hatch_raw_b64" "$hatch_status" "$hatch_expect")"
fi

summary="$(printf '%s\n' "$json_raw" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8").trim();
const exitCode = Number(process.argv[1]);
const installDaemon = process.argv[2] === "1";
const authChoice = process.argv[3];
const raw = Buffer.from(process.argv[4], "base64").toString("utf8");
const hatch = JSON.parse(process.argv[5]);

const expectedNoDaemonHealthFailure =
  !installDaemon &&
  raw.includes("already-running gateway unless you pass --install-daemon");
const scheduledTaskAccessDenied =
  installDaemon && raw.includes("schtasks create failed: ERROR: Access is denied.");

const parsed = input ? JSON.parse(input) : null;
const ok = exitCode === 0;

process.stdout.write(JSON.stringify({
  ok: ok && (!hatch.attempted || (hatch.ok && hatch.matched)),
  exitCode,
  authChoice,
  installDaemon,
  expectedNoDaemonHealthFailure,
  scheduledTaskAccessDenied,
  configWritten: parsed?.workspace != null || raw.includes("Config updated."),
  workspaceDir: typeof parsed?.workspace === "string" ? parsed.workspace : null,
  gateway: parsed?.gateway ?? null,
  hatch,
  error: ok ? null : raw.trim() || `command exited with ${exitCode}`,
  raw: parsed,
}, null, 2) + "\n");
' "$status" "$install_daemon" "$auth_choice" "$raw_b64" "$hatch_json")"

if [[ "$json_mode" == "1" ]]; then
  printf '%s\n' "$summary"
  exit 0
fi

printf '%s\n' "$summary" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const parsed = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(`ok=${parsed.ok}`);
console.log(`authChoice=${parsed.authChoice}`);
console.log(`installDaemon=${parsed.installDaemon}`);
console.log(`expectedNoDaemonHealthFailure=${parsed.expectedNoDaemonHealthFailure}`);
console.log(`scheduledTaskAccessDenied=${parsed.scheduledTaskAccessDenied}`);
console.log(`workspaceDir=${parsed.workspaceDir ?? ""}`);
if (parsed.hatch?.attempted) {
  console.log(`hatchOk=${parsed.hatch.ok}`);
  console.log(`hatchMatched=${parsed.hatch.matched}`);
}
if (parsed.error) {
  console.log(`error=${parsed.error}`);
}
'
