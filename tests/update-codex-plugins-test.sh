#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.local/npm-global/bin"
cat > "$TMPDIR/.local/npm-global/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/codex-args.log"

if [ "$*" = "plugin marketplace upgrade --json" ]; then
  cat <<'JSON'
{"selectedMarketplaces":["test-marketplace"],"upgradedRoots":["/tmp/test-root"],"errors":[]}
JSON
  exit 0
fi

exit 64
EOF
chmod +x "$TMPDIR/.local/npm-global/bin/codex"

HOME="$TMPDIR" PATH="/usr/bin:/bin" "$REPO_ROOT/scripts/update-codex-plugins.sh" > "$TMPDIR/out"

grep -F "selected: test-marketplace" "$TMPDIR/out" >/dev/null
grep -F "upgraded roots: /tmp/test-root" "$TMPDIR/out" >/dev/null
grep -F "Codex plugin marketplaces done" "$TMPDIR/out" >/dev/null
grep -Fx "plugin marketplace upgrade --json" "$TMPDIR/codex-args.log" >/dev/null
