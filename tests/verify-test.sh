#!/usr/bin/env bash
set -euo pipefail

if [ "${AGENT_SCRIPTS_VERIFY_DEP_TEST:-0}" = 1 ]; then
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
ln -s "$(command -v bash)" "$TMPDIR/bin/bash"
ln -s "$(command -v git)" "$TMPDIR/bin/git"

if AGENT_SCRIPTS_VERIFY_DEP_TEST=1 PATH="$TMPDIR/bin" /bin/bash "$REPO_ROOT/scripts/verify.sh" >"$TMPDIR/out" 2>&1; then
  echo "FAIL: verifier accepted a missing Python dependency" >&2
  exit 1
fi

grep -F "required tool not found: python3" "$TMPDIR/out" >/dev/null
grep -F "Install Python 3" "$TMPDIR/out" >/dev/null

mkdir -p "$TMPDIR/pkg-bin"
for tool in bash git node npm jq; do
  ln -s "$(command -v "$tool")" "$TMPDIR/pkg-bin/$tool"
done
printf '%s\n' '#!/bin/sh' 'exit 1' > "$TMPDIR/pkg-bin/python3"
chmod +x "$TMPDIR/pkg-bin/python3"

if AGENT_SCRIPTS_VERIFY_DEP_TEST=1 PATH="$TMPDIR/pkg-bin" /bin/bash "$REPO_ROOT/scripts/verify.sh" >"$TMPDIR/pkg-out" 2>&1; then
  echo "FAIL: verifier accepted missing PyYAML" >&2
  exit 1
fi

grep -F "required Python package not found: PyYAML" "$TMPDIR/pkg-out" >/dev/null
grep -F "python3 -m pip install pyyaml" "$TMPDIR/pkg-out" >/dev/null

mkdir -p "$TMPDIR/jq-bin"
for tool in bash git python3 node npm; do
  ln -s "$(command -v "$tool")" "$TMPDIR/jq-bin/$tool"
done

if AGENT_SCRIPTS_VERIFY_DEP_TEST=1 PATH="$TMPDIR/jq-bin" /bin/bash "$REPO_ROOT/scripts/verify.sh" >"$TMPDIR/jq-out" 2>&1; then
  echo "FAIL: verifier accepted a missing jq dependency" >&2
  exit 1
fi

grep -F "required tool not found: jq" "$TMPDIR/jq-out" >/dev/null
grep -F "Install jq" "$TMPDIR/jq-out" >/dev/null

mkdir -p "$TMPDIR/node-bin"
for tool in bash git python3 npm jq; do
  ln -s "$(command -v "$tool")" "$TMPDIR/node-bin/$tool"
done
printf '%s\n' '#!/bin/sh' 'exit 1' > "$TMPDIR/node-bin/node"
chmod +x "$TMPDIR/node-bin/node"

if AGENT_SCRIPTS_VERIFY_DEP_TEST=1 PATH="$TMPDIR/node-bin" /bin/bash "$REPO_ROOT/scripts/verify.sh" >"$TMPDIR/node-out" 2>&1; then
  echo "FAIL: verifier accepted an unsupported Node.js version" >&2
  exit 1
fi

grep -F "Node.js 22.18 or newer is required" "$TMPDIR/node-out" >/dev/null

echo "verify tests passed"
