#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: prl-openclaw-smoke.sh <vm-name> [--openai-api-key-env <env-var>] [--openai-api-key <key>] [--model <provider/model>] [--install-version <version>] [--install-spec <npm-spec-or-url>] [--overlay-spec <npm-spec-or-url>] [--overlay-source-dir <guest-package-dir>] [--prefix <guest-prefix>] [--skip-gateway] [--json]
EOF
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
model=
install_version=
install_spec=
overlay_spec=
overlay_source_dir=
prefix=
skip_gateway=0
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
    --model)
      model=${2:?missing model}
      shift 2
      ;;
    --install-version)
      install_version=${2:?missing version}
      shift 2
      ;;
    --install-spec)
      install_spec=${2:?missing spec}
      shift 2
      ;;
    --overlay-spec)
      overlay_spec=${2:?missing spec}
      shift 2
      ;;
    --overlay-source-dir)
      overlay_source_dir=${2:?missing source dir}
      shift 2
      ;;
    --prefix)
      prefix=${2:?missing prefix}
      shift 2
      ;;
    --skip-gateway)
      skip_gateway=1
      shift
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
  echo "error: pass only one of --openai-api-key or --openai-api-key-env" >&2
  exit 1
fi

if [[ -n "$install_spec" && -n "$install_version" ]]; then
  echo "error: pass only one of --install-version or --install-spec" >&2
  exit 1
fi

if [[ -n "$overlay_spec" && -n "$overlay_source_dir" ]]; then
  echo "error: pass only one of --overlay-spec or --overlay-source-dir" >&2
  exit 1
fi

if [[ -n "$install_spec" && ( -n "$overlay_spec" || -n "$overlay_source_dir" ) ]]; then
  echo "error: combine either install or overlay, not both" >&2
  exit 1
fi

env_args=()
if [[ -n "$openai_api_key_env" ]]; then
  [[ -n "${!openai_api_key_env:-}" ]] || { echo "error: host env var $openai_api_key_env is empty" >&2; exit 1; }
  env_args+=(--env "OPENAI_API_KEY=${!openai_api_key_env}")
elif [[ -n "$openai_api_key" ]]; then
  env_args+=(--env "OPENAI_API_KEY=$openai_api_key")
fi

if [[ -z "$model" && ( -n "$openai_api_key_env" || -n "$openai_api_key" ) ]]; then
  model=openai/gpt-5.4
fi

setup_action=none
setup_target=
setup_raw=
gateway_boot=unknown
gateway_status_ready=
manual_gateway_kind=
manual_gateway_pid=
manual_gateway_port=18789

json_from_raw() {
  printf '%s\n' "$1" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8");
for (let start = 0; start < input.length; start += 1) {
  if (input[start] !== "{") continue;
  let depth = 0, inString = false, escape = false;
  for (let i = start; i < input.length; i += 1) {
    const ch = input[i];
    if (inString) {
      if (escape) escape = false;
      else if (ch === "\\") escape = true;
      else if (ch === "\"") inString = false;
      continue;
    }
    if (ch === "\"") { inString = true; continue; }
    if (ch === "{") { depth += 1; continue; }
    if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        const candidate = input.slice(start, i + 1);
        try {
          JSON.parse(candidate);
          process.stdout.write(candidate);
          process.exit(0);
        } catch {}
      }
    }
  }
}
process.exit(1);
'
}

json_eval() {
  local json=$1
  local expr=$2
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

wait_for_status_ok() {
  local attempts=${1:-10}
  local delay_s=${2:-1}
  local status
  local i
  for ((i = 1; i <= attempts; i += 1)); do
    status="$("${status_cmd[@]}" 2>/dev/null || true)"
    if [[ -n "${status//$'\n'/}" ]] && [[ "$(json_eval "$status" 'input.rpcOk === true ? "true" : ""')" == "true" ]]; then
      printf '%s\n' "$status"
      return 0
    fi
    sleep "$delay_s"
  done
  return 1
}

cleanup() {
  case "$manual_gateway_kind" in
    macos)
      prl_kill_port_listener "$vm" "$manual_gateway_port" >/dev/null 2>&1 || true
      ;;
    linux)
      if [[ -n "$manual_gateway_pid" ]]; then
        prlctl exec "$vm" --current-user /bin/kill -9 "$manual_gateway_pid" >/dev/null 2>&1 || true
      fi
      prl_linux_stop_gateway_processes "$vm" >/dev/null 2>&1 || true
      ;;
  esac
}
trap cleanup EXIT

os_id=$(prlctl list -i "$vm" | awk -F': ' '/^OS:/{print $2; exit}')
[[ -n "$os_id" ]] || { echo "error: could not detect guest OS for $vm" >&2; exit 1; }

case "$os_id" in
  macosx)
    # shellcheck source=./prl-macos-lib.sh
    source "$SCRIPT_DIR/prl-macos-lib.sh"
    openclaw=("$SCRIPT_DIR/prl-macos-openclaw.sh" "$vm")
    status_cmd=("$SCRIPT_DIR/prl-macos-gateway-status-version.sh" "$vm" --json)
    ;;
  ubuntu|linux)
    # shellcheck source=./prl-linux-lib.sh
    source "$SCRIPT_DIR/prl-linux-lib.sh"
    openclaw=("$SCRIPT_DIR/prl-linux-openclaw.sh" "$vm")
    status_cmd=("$SCRIPT_DIR/prl-linux-gateway-status-version.sh" "$vm" --json)
    ;;
  win-*)
    # shellcheck source=./prl-windows-lib.sh
    source "$SCRIPT_DIR/prl-windows-lib.sh"
    prl_windows_wait_for_user_session "$vm"
    openclaw=("$SCRIPT_DIR/prl-windows-openclaw.sh" "$vm")
    if [[ -n "$prefix" ]]; then
      openclaw+=(--prefix "$prefix")
      status_cmd=("$SCRIPT_DIR/prl-windows-gateway-status-version.sh" "$vm" --prefix "$prefix" --json)
    else
      status_cmd=("$SCRIPT_DIR/prl-windows-gateway-status-version.sh" "$vm" --json)
    fi
    ;;
  *)
    echo "error: unsupported guest OS: $os_id" >&2
    exit 1
    ;;
esac

case "$os_id" in
  macosx|ubuntu|linux)
    if [[ -n "$overlay_spec" || -n "$overlay_source_dir" ]]; then
      echo "error: overlay options are Windows-only today" >&2
      exit 1
    fi
    if [[ -n "$prefix" ]]; then
      echo "error: --prefix is Windows-only today" >&2
      exit 1
    fi
    ;;
  win-*)
    if [[ -n "$prefix" && ( -n "$overlay_spec" || -n "$overlay_source_dir" ) ]]; then
      echo "error: --prefix cannot be combined with overlay options" >&2
      exit 1
    fi
    ;;
esac

run_setup() {
  case "$os_id" in
    macosx)
      if [[ -n "$install_spec" ]]; then
        setup_action=install-spec
        setup_target=$install_spec
        setup_raw="$("$SCRIPT_DIR/prl-macos-install-openclaw.sh" "$vm" --spec "$install_spec" 2>&1)"
      elif [[ -n "$install_version" ]]; then
        setup_action=install-version
        setup_target=$install_version
        setup_raw="$("$SCRIPT_DIR/prl-macos-install-openclaw.sh" "$vm" --version "$install_version" 2>&1)"
      fi
      ;;
    ubuntu|linux)
      if [[ -n "$install_version" ]]; then
        setup_action=install-version
        setup_target=$install_version
        setup_raw="$("$SCRIPT_DIR/prl-linux-install-openclaw.sh" "$vm" --version "$install_version" 2>&1)"
      fi
      ;;
    win-*)
      if [[ -n "$overlay_source_dir" ]]; then
        setup_action=overlay-source-dir
        setup_target=$overlay_source_dir
        setup_raw="$("$SCRIPT_DIR/prl-windows-overlay-openclaw.sh" "$vm" --source-dir "$overlay_source_dir" --json 2>&1)"
      elif [[ -n "$overlay_spec" ]]; then
        setup_action=overlay-spec
        setup_target=$overlay_spec
        setup_raw="$("$SCRIPT_DIR/prl-windows-overlay-openclaw.sh" "$vm" --spec "$overlay_spec" --json 2>&1)"
      elif [[ -n "$install_spec" ]]; then
        setup_action=install-spec
        setup_target=$install_spec
        if [[ -n "$prefix" ]]; then
          setup_raw="$("$SCRIPT_DIR/prl-windows-install-openclaw.sh" "$vm" --spec "$install_spec" --prefix "$prefix" 2>&1)"
        else
          setup_raw="$("$SCRIPT_DIR/prl-windows-install-openclaw.sh" "$vm" --spec "$install_spec" 2>&1)"
        fi
      elif [[ -n "$install_version" ]]; then
        setup_action=install-version
        setup_target=$install_version
        setup_raw="$("$SCRIPT_DIR/prl-windows-install-openclaw.sh" "$vm" --version "$install_version" 2>&1)"
      fi
      ;;
  esac
}

ensure_gateway_ready() {
  local status
  if status="$(wait_for_status_ok 2 1)"; then
    gateway_boot=existing
    gateway_status_ready=$status
    return 0
  fi

  case "$os_id" in
    macosx)
      "${openclaw[@]}" "${env_args[@]}" config set gateway.mode local >/dev/null 2>&1 || true
      "${openclaw[@]}" "${env_args[@]}" gateway install --force >/dev/null 2>&1 || true
      if status="$(wait_for_status_ok 10 1)"; then
        gateway_boot=service
        gateway_status_ready=$status
        return 0
      fi
      prl_kill_port_listener "$vm" "$manual_gateway_port" >/dev/null 2>&1 || true
      manual_gateway_pid="$(prl_run_openclaw_detached_env "$vm" "$manual_gateway_log" gateway run --bind loopback --port "$manual_gateway_port" --force)"
      manual_gateway_kind=macos
      if status="$(wait_for_status_ok 10 1)"; then
        gateway_boot=manual
        gateway_status_ready=$status
        return 0
      fi
      ;;
    ubuntu|linux)
      "${openclaw[@]}" "${env_args[@]}" config set gateway.mode local >/dev/null 2>&1 || true
      prl_linux_stop_gateway_processes "$vm" >/dev/null 2>&1 || true
      manual_gateway_pid="$(prl_linux_run_openclaw_detached_env "$vm" "$manual_gateway_log" gateway run --bind loopback --port "$manual_gateway_port" --force)"
      manual_gateway_kind=linux
      if status="$(wait_for_status_ok 10 1)"; then
        gateway_boot=manual
        gateway_status_ready=$status
        return 0
      fi
      ;;
    win-*)
      prl_windows_start_gateway_detached "$vm"
      prl_windows_wait_for_gateway_port "$vm" "$manual_gateway_port" 60
      if status="$(wait_for_status_ok 10 1)"; then
        gateway_boot=service
        gateway_status_ready=$status
        return 0
      fi
      ;;
  esac

  return 1
}

case "$os_id" in
  macosx)
    manual_gateway_log="/tmp/openclaw-gateway-smoke-$manual_gateway_port.log"
    ;;
  ubuntu|linux)
    manual_gateway_log="/tmp/openclaw-gateway-smoke-$manual_gateway_port.log"
    ;;
esac

run_setup

configured_model=$model
if [[ -n "$model" ]]; then
  case "$os_id" in
    win-*)
      configured_model=$(prl_windows_set_primary_model "$vm" "$model" | tail -n 1 | tr -d '\r')
      ;;
    *)
      "${openclaw[@]}" "${env_args[@]}" config set agents.defaults.model.primary "$model" >/dev/null
      configured_model=$("${openclaw[@]}" "${env_args[@]}" config get agents.defaults.model.primary | tr -d '\r')
      ;;
  esac
else
  set +e
  configured_model=$("${openclaw[@]}" "${env_args[@]}" config get agents.defaults.model.primary 2>/dev/null | tr -d '\r')
  set -e
fi

version_raw=$("${openclaw[@]}" "${env_args[@]}" --version 2>&1 || true)

local_raw=$("${openclaw[@]}" "${env_args[@]}" agent --local --agent main --json --thinking low -m VM-SMOKE-LOCAL-OK 2>&1 || true)
local_json=$(json_from_raw "$local_raw" 2>/dev/null || true)

gateway_raw=
gateway_json=
status_raw=
status_json=
if [[ "$skip_gateway" != "1" ]]; then
  if ensure_gateway_ready; then
    status_raw=$gateway_status_ready
  else
    status_raw=
  fi
  status_json=$(json_from_raw "$status_raw" 2>/dev/null || true)
  gateway_raw=$("${openclaw[@]}" "${env_args[@]}" agent --agent main --json --thinking low -m VM-SMOKE-GATEWAY-OK 2>&1 || true)
  gateway_json=$(json_from_raw "$gateway_raw" 2>/dev/null || true)
fi

summary=$(
  VERSION_RAW="$version_raw" \
  CONFIGURED_MODEL="$configured_model" \
  SETUP_ACTION="$setup_action" \
  SETUP_TARGET="$setup_target" \
  SETUP_RAW="$setup_raw" \
  GATEWAY_BOOT="$gateway_boot" \
  LOCAL_RAW="$local_raw" \
  LOCAL_JSON="$local_json" \
  STATUS_RAW="$status_raw" \
  STATUS_JSON="$status_json" \
  GATEWAY_RAW="$gateway_raw" \
  GATEWAY_JSON="$gateway_json" \
  OS_ID="$os_id" \
  /opt/homebrew/bin/node <<'EOF'
function parseMaybe(name) {
  const value = process.env[name];
  if (!value) return null;
  try { return JSON.parse(value); } catch { return null; }
}
const local = parseMaybe("LOCAL_JSON");
const gateway = parseMaybe("GATEWAY_JSON");
const status = parseMaybe("STATUS_JSON");
const localText = local?.payloads?.[0]?.text ?? local?.result?.payloads?.[0]?.text ?? null;
const gatewayText = gateway?.result?.payloads?.[0]?.text ?? gateway?.payloads?.[0]?.text ?? null;
const localMeta = local?.meta ?? local?.result?.meta ?? {};
const gatewayMeta = gateway?.result?.meta ?? gateway?.meta ?? {};
function isBootstrapPrompt(text) {
  if (typeof text !== "string" || text.trim().length === 0) return false;
  const normalized = text.toLowerCase();
  return (
    normalized.includes("blank slate") ||
    normalized.includes("setup questions") ||
    (normalized.includes("who am i?") && normalized.includes("who are you?")) ||
    normalized.includes("identity files") ||
    normalized.includes("name, vibe")
  );
}
const localBootstrap = isBootstrapPrompt(localText);
const gatewayBootstrap = isBootstrapPrompt(gatewayText);
const summary = {
  os: process.env.OS_ID,
  version: (process.env.VERSION_RAW || "").trim() || null,
  configuredModel: (process.env.CONFIGURED_MODEL || "").trim() || null,
  setup: process.env.SETUP_ACTION && process.env.SETUP_ACTION !== "none"
    ? {
        action: process.env.SETUP_ACTION,
        target: (process.env.SETUP_TARGET || "").trim() || null,
        raw: (process.env.SETUP_RAW || "").trim() || null,
      }
    : null,
  local: {
    ok: localText === "VM-SMOKE-LOCAL-OK" || localBootstrap,
    exact: localText === "VM-SMOKE-LOCAL-OK",
    bootstrapPrompt: localBootstrap,
    text: localText,
    provider: localMeta?.agentMeta?.provider ?? null,
    model: localMeta?.agentMeta?.model ?? null,
    sessionId: localMeta?.agentMeta?.sessionId ?? null,
    raw: local ? null : ((process.env.LOCAL_RAW || "").trim() || null),
  },
  gatewayStatus: status,
  gateway: gateway || process.env.GATEWAY_RAW
    ? {
        boot: (process.env.GATEWAY_BOOT || "").trim() || null,
        ok: gatewayText === "VM-SMOKE-GATEWAY-OK" || gatewayBootstrap,
        exact: gatewayText === "VM-SMOKE-GATEWAY-OK",
        bootstrapPrompt: gatewayBootstrap,
        text: gatewayText,
        provider: gatewayMeta?.agentMeta?.provider ?? null,
        model: gatewayMeta?.agentMeta?.model ?? null,
        sessionId: gatewayMeta?.agentMeta?.sessionId ?? null,
        raw: gateway ? null : ((process.env.GATEWAY_RAW || "").trim() || null),
      }
    : null,
};
summary.ok = Boolean(summary.local.ok) && (summary.gateway == null || summary.gateway.ok);
process.stdout.write(JSON.stringify(summary, null, 2));
EOF
)

if [[ "$json_mode" == "1" ]]; then
  printf '%s\n' "$summary"
  exit 0
fi

printf '%s\n' "$summary" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const parsed = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(`ok=${parsed.ok}`);
console.log(`os=${parsed.os}`);
console.log(`version=${parsed.version ?? ""}`);
console.log(`configuredModel=${parsed.configuredModel ?? ""}`);
console.log(`localOk=${parsed.local?.ok}`);
console.log(`localModel=${parsed.local?.model ?? ""}`);
if (parsed.gateway) {
  console.log(`gatewayOk=${parsed.gateway.ok}`);
  console.log(`gatewayModel=${parsed.gateway.model ?? ""}`);
}
'
