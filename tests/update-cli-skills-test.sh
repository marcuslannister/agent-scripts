#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/scripts" "$TMP_ROOT/bin"
cp "$REPO_ROOT/scripts/update-cli-skills.sh" "$TMP_ROOT/scripts/"
cat > "$TMP_ROOT/bin/npx" <<'BASH'
#!/usr/bin/env bash
printf 'generic npx updater called\n' >> "$NPX_LOG"
exit 99
BASH
chmod +x "$TMP_ROOT/bin/npx"

NPX_LOG="$TMP_ROOT/npx.log" PATH="$TMP_ROOT/bin:$PATH" \
  "$TMP_ROOT/scripts/update-cli-skills.sh" > "$TMP_ROOT/out"

test ! -e "$TMP_ROOT/npx.log"
grep -F 'cli-skills retired; use update-skill-topology.sh' "$TMP_ROOT/out" >/dev/null

echo "update-cli-skills tests passed"
