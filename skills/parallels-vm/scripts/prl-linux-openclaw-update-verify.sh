#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-linux-lib.sh
source "$SCRIPT_DIR/prl-linux-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> [--from-version <version>] [--to-tag <tag>] [--profile <name>] [--state-dir <dir>] [--port <port>] [--install-url <url>]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage

vm=$1
shift

from_version=2026.3.7
to_tag=latest
profile=
state_dir=
port=18789
install_url=https://openclaw.ai/install.sh
manual_gateway_pid=
tmp_dir=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-version)
      from_version=${2:?missing version}
      shift 2
      ;;
    --to-tag)
      to_tag=${2:?missing tag}
      shift 2
      ;;
    --profile)
      profile=${2:?missing profile}
      shift 2
      ;;
    --state-dir)
      state_dir=${2:?missing state dir}
      shift 2
      ;;
    --port)
      port=${2:?missing port}
      shift 2
      ;;
    --install-url)
      install_url=${2:?missing install url}
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

cleanup() {
  if [[ -n "$manual_gateway_pid" ]]; then
    prlctl exec "$vm" --current-user /bin/kill -9 "$manual_gateway_pid" >/dev/null 2>&1 || true
  fi
  prl_linux_stop_gateway_processes "$vm" >/dev/null 2>&1 || true
  if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

env_args=()
[[ -n "$profile" ]] && env_args+=("OPENCLAW_PROFILE=$profile")
[[ -n "$state_dir" ]] && env_args+=("OPENCLAW_STATE_DIR=$state_dir")

run_openclaw() {
  local cmd=("$SCRIPT_DIR/prl-linux-openclaw.sh" "$vm")
  local env_arg
  for env_arg in "${env_args[@]}"; do
    cmd+=(--env "$env_arg")
  done
  cmd+=("$@")
  "${cmd[@]}"
}

status_json() {
  local cmd=("$SCRIPT_DIR/prl-linux-gateway-status-version.sh" "$vm")
  local env_arg
  for env_arg in "${env_args[@]}"; do
    case "$env_arg" in
      OPENCLAW_PROFILE=*)
        cmd+=(--profile "${env_arg#OPENCLAW_PROFILE=}")
        ;;
      OPENCLAW_STATE_DIR=*)
        cmd+=(--state-dir "${env_arg#OPENCLAW_STATE_DIR=}")
        ;;
    esac
  done
  cmd+=(--json)
  "${cmd[@]}"
}

json_field() {
  local json=$1
  local expr=$2
  if [[ -z "${json//$'\n'/}" ]]; then
    printf ''
    return 0
  fi
  printf '%s\n' "$json" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(0, "utf8"));
const expr = process.argv[1];
const value = Function("input", `return (${expr});`)(input);
if (value === undefined || value === null) {
  process.stdout.write("");
} else if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
' "$expr"
}

wait_for_gateway() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    local status
    status="$(status_json 2>/dev/null || true)"
    if [[ -z "${status//$'\n'/}" ]]; then
      sleep 1
      continue
    fi
    if [[ "$(json_field "$status" 'input.rpcOk === true ? "true" : ""')" == "true" ]]; then
      printf '%s\n' "$status"
      return 0
    fi
    sleep 1
  done
  return 1
}

start_manual_gateway() {
  local log_path="/tmp/openclaw-gateway-linux-smoke-${profile:-default}-$port.log"
  prl_linux_stop_gateway_processes "$vm" >/dev/null 2>&1 || true
  manual_gateway_pid="$(prl_linux_run_openclaw_detached_env "$vm" "${env_args[@]}" "$log_path" gateway run --bind loopback --port "$port" --force)"
}

install_cmd=("$SCRIPT_DIR/prl-linux-install-openclaw.sh" "$vm" --version "$from_version" --install-url "$install_url")
if [[ -n "$profile" ]]; then
  install_cmd+=(--profile "$profile")
fi
if [[ -n "$state_dir" ]]; then
  install_cmd+=(--state-dir "$state_dir")
fi

before_install="$("${install_cmd[@]}")"
before_cli_version="$(prl_linux_parse_openclaw_version "$before_install")"

run_openclaw config set gateway.mode local >/dev/null 2>&1 || true
start_manual_gateway
before_status="$(wait_for_gateway)"
prlctl exec "$vm" --current-user /bin/kill -9 "$manual_gateway_pid" >/dev/null 2>&1 || true
manual_gateway_pid=

update_install_cmd=("$SCRIPT_DIR/prl-linux-install-openclaw.sh" "$vm" --version "$to_tag" --install-url "$install_url")
if [[ -n "$profile" ]]; then
  update_install_cmd+=(--profile "$profile")
fi
if [[ -n "$state_dir" ]]; then
  update_install_cmd+=(--state-dir "$state_dir")
fi

after_install="$("${update_install_cmd[@]}")"
after_install_version="$(prl_linux_parse_openclaw_version "$after_install")"
update_json="$(/opt/homebrew/bin/node -e '
const beforeVersion = process.argv[1];
const afterVersion = process.argv[2];
process.stdout.write(JSON.stringify({
  status: "ok",
  mode: "installer",
  before: { version: beforeVersion },
  after: { version: afterVersion },
}));
' "$before_cli_version" "$after_install_version")"

after_cli_raw="$(run_openclaw --version)"
after_cli_version="$(prl_linux_parse_openclaw_version "$after_cli_raw")"

run_openclaw config set gateway.mode local >/dev/null 2>&1 || true
start_manual_gateway
after_status="$(wait_for_gateway)"

tmp_dir=$(mktemp -d)
printf '%s\n' "$before_status" >"$tmp_dir/before-status.json"
printf '%s\n' "$update_json" >"$tmp_dir/update.json"
printf '%s\n' "$after_status" >"$tmp_dir/after-status.json"

/opt/homebrew/bin/node - "$tmp_dir/before-status.json" "$tmp_dir/update.json" "$tmp_dir/after-status.json" "$after_cli_version" <<'EOF'
const fs = require("fs");
const [beforePath, updatePath, afterPath, afterCliVersion] = process.argv.slice(2);
const beforeStatus = JSON.parse(fs.readFileSync(beforePath, "utf8"));
const update = JSON.parse(fs.readFileSync(updatePath, "utf8"));
const afterStatus = JSON.parse(fs.readFileSync(afterPath, "utf8"));
const summary = {
  ok: true,
  before: {
    cliVersion: update.before?.version ?? null,
    gatewayMode: "manual",
    statusRuntimeVersion: beforeStatus.runtimeVersion ?? null,
    rpcOk: beforeStatus.rpcOk === true,
    servicePid: beforeStatus.servicePid ?? null,
    listenerPid: beforeStatus.listenerPid ?? null,
    port: beforeStatus.port ?? null,
  },
  update: {
    status: update.status ?? null,
    mode: update.mode ?? null,
    beforeVersion: update.before?.version ?? null,
    afterVersion: update.after?.version ?? null,
  },
  after: {
    cliVersion: afterCliVersion || null,
    gatewayMode: "manual",
    statusRuntimeVersion: afterStatus.runtimeVersion ?? null,
    rpcOk: afterStatus.rpcOk === true,
    servicePid: afterStatus.servicePid ?? null,
    listenerPid: afterStatus.listenerPid ?? null,
    port: afterStatus.port ?? null,
  },
};

if (summary.update.status !== "ok") {
  summary.ok = false;
}
if (!summary.before.rpcOk || !summary.after.rpcOk) {
  summary.ok = false;
}
if (summary.update.afterVersion && summary.after.cliVersion && summary.update.afterVersion !== summary.after.cliVersion) {
  summary.ok = false;
}
if (summary.after.statusRuntimeVersion && summary.after.cliVersion && summary.after.statusRuntimeVersion !== summary.after.cliVersion) {
  summary.ok = false;
}

process.stdout.write(JSON.stringify(summary, null, 2) + "\n");
process.exit(summary.ok ? 0 : 1);
EOF
