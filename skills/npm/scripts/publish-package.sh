#!/usr/bin/env bash
set -euo pipefail
set +x

usage() {
  cat <<'USAGE'
Usage:
  publish-package.sh [--account ACCOUNT] [--item ITEM] [--access ACCESS] [--tag TAG]

Publishes the package in the current directory through a temporary authenticated
npmrc. Must run inside the persistent tmux session used for 1Password access.
USAGE
}

ACCOUNT="${NPM_OP_ACCOUNT:-my.1password.com}"
ITEM="${NPM_OP_ITEM:-npmjs}"
REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org/}"
ACCESS="public"
TAG="latest"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT="${2:?missing account}"; shift 2 ;;
    --item) ITEM="${2:?missing item}"; shift 2 ;;
    --access) ACCESS="${2:?missing access}"; shift 2 ;;
    --tag) TAG="${2:?missing tag}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "${TMUX:-}" ]; then
  echo "refusing to run: npm auth must stay inside one persistent tmux session" >&2
  exit 2
fi

for bin in op node npm; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing required binary: $bin" >&2; exit 2; }
done
test -f package.json || { echo "package.json not found in current directory" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d /tmp/npm-publish.XXXXXX)"
NPMRC="$WORK/npmrc"
cleanup() {
  rm -rf "$WORK"
  unset ITEM_JSON NPM_OTP NPMRC SA_TOKEN
}
trap cleanup EXIT

redact() {
  sed -E 's/(npm_[A-Za-z0-9_]+)/npm_REDACTED/g; s/[0-9]{6}/OTP_REDACTED/g'
}

name="$(node -p 'require("./package.json").name')"
version="$(node -p 'require("./package.json").version')"
if npm view "$name@$version" version >/dev/null 2>&1; then
  echo "$name@$version is already published" >&2
  exit 5
fi

SA_TOKEN="${OP_SERVICE_ACCOUNT_TOKEN:-${MOLTY_OP_SERVICE_ACCOUNT_TOKEN:-}}"
AUTH_MODE="desktop"
if [ -n "$SA_TOKEN" ] && ITEM_JSON="$(OP_SERVICE_ACCOUNT_TOKEN="$SA_TOKEN" op item get "$ITEM" --vault Molty --format json 2>/dev/null)"; then
  AUTH_MODE="service"
  echo "1Password access: service account"
else
  unset OP_SERVICE_ACCOUNT_TOKEN MOLTY_OP_SERVICE_ACCOUNT_TOKEN SA_TOKEN
  op signin --account "$ACCOUNT" >/dev/null
  op whoami --account "$ACCOUNT" >/dev/null
  ITEM_JSON="$(op item get "$ITEM" --account "$ACCOUNT" --format json)"
  echo "1Password access: desktop"
fi

current_otp() {
  if [ "$AUTH_MODE" = "service" ]; then
    OP_SERVICE_ACCOUNT_TOKEN="$SA_TOKEN" op item get "$ITEM" --vault Molty --otp 2>/dev/null | tr -d '[:space:]'
  else
    op item get "$ITEM" --account "$ACCOUNT" --otp 2>/dev/null | tr -d '[:space:]'
  fi
}

NPM_OTP="$(current_otp)"
case "$NPM_OTP" in
  [0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "$ITEM has no usable six-digit OTP field" >&2; exit 3 ;;
esac

login_log="$WORK/npm-login.log"
printf "%s" "$ITEM_JSON" |
  NPM_OTP="$NPM_OTP" NPMRC="$NPMRC" REGISTRY="$REGISTRY" \
  node "$SCRIPT_DIR/npm-auth-login.mjs" >"$login_log" 2>&1 || {
    echo "npm registry login failed" >&2
    redact <"$login_log" >&2
    exit 3
  }
unset ITEM_JSON
redact <"$login_log"

who="$(NPM_CONFIG_USERCONFIG="$NPMRC" npm whoami 2>"$WORK/npm-whoami.log" || true)"
if [ -z "$who" ]; then
  echo "npm auth check failed" >&2
  redact <"$WORK/npm-whoami.log" >&2
  exit 4
fi
echo "npm auth ok as $who"

publish_log="$WORK/npm-publish.log"
NPM_OTP="$(current_otp)"
if ! NPM_CONFIG_USERCONFIG="$NPMRC" npm publish --access "$ACCESS" --tag "$TAG" --otp "$NPM_OTP" >"$publish_log" 2>&1; then
  if grep -qiE 'otp|one-time|two-factor|2fa|EOTP' "$publish_log"; then
    echo "publish OTP expired; retrying once with a fresh OTP" >&2
    NPM_OTP="$(current_otp)"
    NPM_CONFIG_USERCONFIG="$NPMRC" npm publish --access "$ACCESS" --tag "$TAG" --otp "$NPM_OTP" >"$publish_log" 2>&1 || {
      redact <"$publish_log" >&2
      exit 6
    }
  else
    redact <"$publish_log" >&2
    exit 6
  fi
fi
redact <"$publish_log"

for _ in {1..12}; do
  published="$(npm view "$name@$version" version 2>/dev/null || true)"
  if [ "$published" = "$version" ]; then
    echo "registry version verified: $name@$published"
    exit 0
  fi
  sleep 5
done
echo "registry did not expose $name@$version in time" >&2
exit 7
