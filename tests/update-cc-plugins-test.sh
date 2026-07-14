#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_UNDER_TEST:-$REPO_ROOT/scripts/update-cc-plugins.sh}"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/bin"
cp "$SCRIPT" "$FIXTURE/scripts/update-cc-plugins.sh"

cat > "$FIXTURE/scripts/update-skill-topology.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$TOPOLOGY_ARGS_LOG"
printf 'topology delegated\n'
BASH

cat > "$FIXTURE/bin/claude" <<'BASH'
#!/usr/bin/env bash
printf 'legacy Claude mutation attempted: %s\n' "$*" >&2
exit 99
BASH
chmod +x "$FIXTURE/scripts/"*.sh "$FIXTURE/bin/claude"

TOPOLOGY_ARGS_LOG="$FIXTURE/args.log" PATH="$FIXTURE/bin:$PATH" \
  "$FIXTURE/scripts/update-cc-plugins.sh" --check --json > "$FIXTURE/out"

printf '%s\n' --check --json > "$FIXTURE/expected-args.log"
cmp -s "$FIXTURE/expected-args.log" "$FIXTURE/args.log"
grep -Fx 'topology delegated' "$FIXTURE/out" >/dev/null

echo "update-cc-plugins tests passed"
