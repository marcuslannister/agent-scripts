#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d /tmp/npm-auth-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

WORK="$TEST_ROOT/work"
NPMRC="$WORK/npmrc"
REGISTRY="https://registry.npmjs.org/"
mkdir -p "$WORK" "$TEST_ROOT/bin" "$TEST_ROOT/caller"
printf '%s\n' '//registry.npmjs.org/:_authToken=fresh-token' >"$NPMRC"
printf '%s\n' '//registry.npmjs.org/:_authToken=stale-token' >"$TEST_ROOT/caller/.npmrc"

cat >"$TEST_ROOT/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test "$PWD" = "$EXPECTED_PWD"
test "$NPM_CONFIG_USERCONFIG" = "$EXPECTED_NPMRC"
if env | grep -Fq 'npm_config_//registry.npmjs.org/:_authToken='; then
  echo "npm token leaked into environment" >&2
  exit 1
fi
test "$1" = "--registry"
test "$2" = "https://registry.npmjs.org/"
test "$3" = "whoami"
printf 'steipete\n'
EOF
chmod +x "$TEST_ROOT/bin/npm"

# shellcheck source=npm-auth.sh
source "$SCRIPT_DIR/npm-auth.sh"

result="$(
  cd "$TEST_ROOT/caller"
  EXPECTED_PWD="$WORK" EXPECTED_NPMRC="$NPMRC" PATH="$TEST_ROOT/bin:$PATH" npm_auth_whoami
)"
test "$result" = "steipete"

echo "npm auth isolation and token handling: ok"
