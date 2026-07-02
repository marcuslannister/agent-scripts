#!/usr/bin/env bash
set -euo pipefail
set +x

usage() {
  cat <<'USAGE'
Usage:
  reserve-packages.sh [--dry-run] [--account ACCOUNT] [--item ITEM] <package...>

Publishes 0.0.0 placeholder packages to npm to reserve names.

Security:
  Must run inside tmux. Reads the npm 1Password item once, creates a temp npmrc,
  publishes packages, then deletes temp auth/work files. Secret values are never
  printed.

Defaults:
  account:  my.1password.com
  item:     npmjs
  registry: https://registry.npmjs.org/
USAGE
}

ACCOUNT="${NPM_OP_ACCOUNT:-my.1password.com}"
ITEM="${NPM_OP_ITEM:-npmjs}"
REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org/}"
DRY_RUN=0
PACKAGES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --account)
      ACCOUNT="${2:?missing account}"
      shift 2
      ;;
    --item)
      ITEM="${2:?missing item}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      PACKAGES+=("$@")
      break
      ;;
    -*)
      echo "unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      PACKAGES+=("$1")
      shift
      ;;
  esac
done

if [ "${#PACKAGES[@]}" -eq 0 ]; then
  usage >&2
  exit 2
fi

if [ -z "${TMUX:-}" ]; then
  echo "refusing to run: this script reads 1Password and must run inside a persistent tmux session" >&2
  exit 2
fi

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required binary: $1" >&2
    exit 2
  }
}

need_bin op
need_bin node
need_bin npm

WORK="$(mktemp -d /tmp/npm-reserve.XXXXXX)"
NPMRC="/tmp/npm-reserve-npmrc.$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cleanup() {
  rm -rf "$WORK" "$NPMRC"
  unset ITEM_JSON NPM_OTP NPMRC REGISTRY SA_TOKEN
}
trap cleanup EXIT

redact() {
  sed -E 's/(npm_[A-Za-z0-9_]+)/npm_REDACTED/g; s/[0-9]{6}/OTP_REDACTED/g'
}

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
echo "op auth ok; reading npm item once: $ITEM"

current_otp() {
  if [ "$AUTH_MODE" = "service" ]; then
    OP_SERVICE_ACCOUNT_TOKEN="$SA_TOKEN" op item get "$ITEM" --vault Molty --otp 2>/dev/null | tr -d '[:space:]' || true
  else
    op item get "$ITEM" --account "$ACCOUNT" --otp 2>/dev/null | tr -d '[:space:]' || true
  fi
}

NPM_OTP="$(current_otp)"
case "$NPM_OTP" in
  [0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  "")
    echo "$ITEM has no usable six-digit OTP field" >&2
    exit 3
    ;;
  *)
    echo "$ITEM OTP output is not six digits; refusing to use it" >&2
    exit 3
    ;;
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

cat > "$WORK/README.md" <<'EOF'
# Reserved package

This package name is reserved for a future project.

It does not provide a stable public API yet.
EOF

reserve_pkg() {
  local name="$1"
  if NPM_CONFIG_USERCONFIG="$NPMRC" npm view "$name" version >/dev/null 2>&1; then
    echo "already taken: $name"
    return 0
  fi
  if NPM_CONFIG_USERCONFIG="$NPMRC" npm access get status "$name" >/dev/null 2>&1; then
    echo "already reserved: $name"
    return 0
  fi

  local dir="$WORK/$name"
  mkdir -p "$dir"
  cp "$WORK/README.md" "$dir/README.md"
  cat > "$dir/package.json" <<EOF
{
  "name": "$name",
  "version": "0.0.0",
  "description": "Reserved package name.",
  "license": "MIT",
  "private": false
}
EOF

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would publish: $name"
    return 0
  fi

  local safe_name
  safe_name="$(printf "%s" "$name" | tr '/@' '__')"
  local log="$WORK/npm-publish-$safe_name.log"
  local otp
  otp="$(current_otp)"
  if [ -n "$otp" ] && (cd "$dir" && NPM_CONFIG_USERCONFIG="$NPMRC" npm publish --access public --otp "$otp" >"$log" 2>&1); then
    echo "published: $name"
    return 0
  fi

  if grep -qiE 'otp|one-time|two-factor|2fa|EOTP' "$log"; then
    echo "publish needs/failed OTP for $name; retrying once with fresh OTP" >&2
    sleep 31
    otp="$(current_otp)"
    if [ -n "$otp" ] && (cd "$dir" && NPM_CONFIG_USERCONFIG="$NPMRC" npm publish --access public --otp "$otp" >"$log" 2>&1); then
      echo "published: $name"
      return 0
    fi
  fi

  echo "publish failed: $name" >&2
  if grep -qi 'previously published versions' "$log"; then
    echo "already reserved: $name"
    return 0
  fi
  redact <"$log" >&2
  return 1
}

failed=0
for pkg in "${PACKAGES[@]}"; do
  if ! reserve_pkg "$pkg"; then
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "done"
else
  echo "done with publish failures; see lines above"
  exit 1
fi
