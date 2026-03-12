#!/usr/bin/env bash
set -euo pipefail

PRL_LINUX_GUEST_PATH_BASE=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

prl_linux_die() {
  echo "error: $*" >&2
  exit 1
}

prl_linux_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || prl_linux_die "$1 not found"
}

prl_linux_require_prlctl() {
  prl_linux_require_cmd prlctl
}

prl_linux_exec_sh() {
  local vm=$1
  shift
  prlctl exec "$vm" --current-user /usr/bin/env PATH="$PRL_LINUX_GUEST_PATH_BASE" \
    /bin/sh -lc "PATH=\"\$HOME/.local/bin:$PRL_LINUX_GUEST_PATH_BASE\"; $*"
}

prl_linux_exec_env() {
  local vm=$1
  shift
  local env_args=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    env_args+=("$1")
    shift
  done
  prlctl exec "$vm" --current-user /usr/bin/env PATH="$PRL_LINUX_GUEST_PATH_BASE" \
    "${env_args[@]}" "$@"
}

prl_linux_resolve_openclaw_cmd() {
  local vm=$1
  prlctl exec "$vm" --current-user /bin/sh -lc 'PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; for candidate in "$HOME/.local/bin/openclaw" "$(command -v openclaw 2>/dev/null)" /usr/local/bin/openclaw /usr/bin/openclaw; do if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf "%s\n" "$candidate"; exit 0; fi; done; exit 1'
}

prl_linux_run_openclaw_env() {
  local vm=$1
  shift
  local env_args=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    env_args+=("$1")
    shift
  done
  local openclaw_cmd
  openclaw_cmd=$(prl_linux_resolve_openclaw_cmd "$vm") || prl_linux_die "guest OpenClaw command not found"
  prl_linux_exec_env "$vm" "${env_args[@]}" "$openclaw_cmd" "$@"
}

prl_linux_download_to_guest() {
  local vm=$1
  local url=$2
  local guest_path=$3
  local guest_dir
  guest_dir=$(dirname "$guest_path")
  prlctl exec "$vm" --current-user /bin/mkdir -p "$guest_dir"
  prl_linux_exec_sh "$vm" "if command -v curl >/dev/null 2>&1; then curl -fsSL -o '$guest_path' '$url'; elif command -v wget >/dev/null 2>&1; then wget -qO '$guest_path' '$url'; else echo 'error: guest needs curl or wget' >&2; exit 1; fi"
}

prl_linux_spawn_detached() {
  local vm=$1
  shift
  local env_args=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    env_args+=("$1")
    shift
  done
  local log_path=${1:?missing log path}
  shift
  local quoted_cmd=
  local quoted_env=
  local arg
  for arg in "$@"; do
    printf -v quoted_cmd '%s %q' "$quoted_cmd" "$arg"
  done
  for arg in "${env_args[@]}"; do
    printf -v quoted_env '%s %q' "$quoted_env" "$arg"
  done
  prl_linux_exec_sh "$vm" "nohup env$quoted_env$quoted_cmd > \"$log_path\" 2>&1 </dev/null & echo \$!"
}

prl_linux_run_openclaw_detached_env() {
  local vm=$1
  shift
  local env_args=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    env_args+=("$1")
    shift
  done
  local log_path=${1:?missing log path}
  shift
  local openclaw_cmd
  openclaw_cmd=$(prl_linux_resolve_openclaw_cmd "$vm") || prl_linux_die "guest OpenClaw command not found"
  prl_linux_spawn_detached "$vm" "${env_args[@]}" "$log_path" "$openclaw_cmd" "$@"
}

prl_linux_stop_gateway_processes() {
  local vm=$1
  prl_linux_exec_sh "$vm" "pkill -f 'openclaw-gateway' >/dev/null 2>&1 || true; pkill -f 'openclaw.*gateway' >/dev/null 2>&1 || true; pkill -f 'node.*openclaw.*gateway' >/dev/null 2>&1 || true"
}

prl_linux_parse_openclaw_version() {
  local raw=$1
  local version
  version=$(printf '%s\n' "$raw" | /usr/bin/perl -ne 'if (/(20[0-9]{2}\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?)/) { print "$1\n"; exit 0 }')
  [[ -n "$version" ]] || prl_linux_die "could not parse OpenClaw version from: $raw"
  printf '%s\n' "$version"
}
