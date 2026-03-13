#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./prl-windows-lib.sh
source "$SCRIPT_DIR/prl-windows-lib.sh"

usage() {
  echo "usage: $(basename "$0") <vm-name> --spec <npm-spec-or-url> [--json]" >&2
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

spec=
json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)
      spec=${2:?missing spec}
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

[[ -n "$spec" ]] || prl_windows_die "--spec is required"

prl_windows_require_prlctl
prl_windows_wait_for_user_session "$vm"

spec_ps=$(
  printf '%s' "$spec" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const value = fs.readFileSync(0, "utf8");
process.stdout.write("'"'"'" + value.replace(/'"'"'/g, "'"'"''"'"'") + "'"'"'");
'
)

script=$(cat <<EOF
\$ProgressPreference = 'SilentlyContinue'
\$sourceSpec = $spec_ps
\$portableRoot = Join-Path \$env:LOCALAPPDATA 'OpenClaw\\deps\\portable-git'
\$portableEntries = @(
  (Join-Path \$portableRoot 'mingw64\\bin'),
  (Join-Path \$portableRoot 'usr\\bin'),
  (Join-Path \$portableRoot 'cmd'),
  (Join-Path \$portableRoot 'bin')
) | Where-Object { Test-Path \$_ }
if (\$portableEntries.Count -gt 0) {
  \$env:Path = ((\$portableEntries + @(\$env:Path)) -join ';')
}
\$root = Join-Path \$env:TEMP 'openclaw-overlay'
New-Item -ItemType Directory -Force -Path \$root | Out-Null
\$tgz = Join-Path \$root 'openclaw-overlay.tgz'
if (Test-Path \$tgz) { Remove-Item -Force \$tgz }
if (\$sourceSpec -match '^(https?|file)://') {
  Invoke-WebRequest -UseBasicParsing \$sourceSpec -OutFile \$tgz
} else {
  \$env:NPM_CONFIG_LOGLEVEL = 'error'
  \$env:NPM_CONFIG_UPDATE_NOTIFIER = 'false'
  \$env:NPM_CONFIG_FUND = 'false'
  \$env:NPM_CONFIG_AUDIT = 'false'
  & npm.cmd pack \$sourceSpec --pack-destination \$root --silent | Out-Null
  \$packed = Get-ChildItem -Path \$root -Filter '*.tgz' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if (-not \$packed) {
    throw 'overlay pack did not produce a tgz'
  }
  \$tgz = \$packed.FullName
}
\$pkgRoot = Join-Path \$root 'pkg'
if (Test-Path \$pkgRoot) { Remove-Item -Recurse -Force \$pkgRoot }
New-Item -ItemType Directory -Force -Path \$pkgRoot | Out-Null
tar -xf \$tgz -C \$pkgRoot
\$source = Join-Path \$pkgRoot 'package'
\$globalRoot = (& npm.cmd root -g).Trim()
\$installedDir = Join-Path \$globalRoot 'openclaw'
if (-not (Test-Path \$installedDir)) {
  throw 'global openclaw install not found; install OpenClaw first, then overlay'
}
Copy-Item -Recurse -Force (Join-Path \$source '*') \$installedDir
\$command = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
if (-not \$command) {
  \$knownPaths = @(
    (Join-Path \$env:APPDATA 'npm\\openclaw.cmd'),
    (Join-Path \$env:LOCALAPPDATA 'pnpm\\openclaw.cmd'),
    (Join-Path \$env:USERPROFILE 'AppData\\Roaming\\npm\\openclaw.cmd')
  ) | Where-Object { \$_ -and (Test-Path \$_) }
  if (\$knownPaths.Count -gt 0) {
    \$command = [pscustomobject]@{ Source = \$knownPaths[0] }
  }
}
if (-not \$command -or -not \$command.Source) {
  throw 'openclaw cmd not found after overlay'
}
\$versionRaw = & \$command.Source --version 2>&1 | Out-String
[pscustomobject]@{
  ok = \$true
  spec = \$sourceSpec
  tgzPath = \$tgz
  installedDir = \$installedDir
  commandPath = \$command.Source
  version = \$versionRaw.Trim()
} | ConvertTo-Json -Compress
EOF
)

raw="$(prl_windows_exec_ps_script "$vm" "$script" 2>&1)"
cleaned="$(printf '%s\n' "$raw" | prl_windows_strip_clixml)"
json="$(printf '%s\n' "$cleaned" | prl_windows_extract_json)"

if [[ "$json_mode" == "1" ]]; then
  printf '%s\n' "$json"
  exit 0
fi

printf '%s\n' "$json" | /opt/homebrew/bin/node -e '
const fs = require("fs");
const parsed = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(`ok=${parsed.ok}`);
console.log(`spec=${parsed.spec}`);
console.log(`version=${parsed.version}`);
console.log(`commandPath=${parsed.commandPath}`);
console.log(`installedDir=${parsed.installedDir}`);
'
