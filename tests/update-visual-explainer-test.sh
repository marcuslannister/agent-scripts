#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/Projects/visual-explainer/.git" "$TMPDIR/Projects/visual-explainer/plugins/visual-explainer/commands"
mkdir -p "$TMPDIR/.codex"
ln -s "../Projects/visual-explainer/plugins/visual-explainer" "$TMPDIR/.codex/visual-explainer"
cat > "$TMPDIR/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/git-args.log"
exit 0
EOF
chmod +x "$TMPDIR/bin/git"

HOME="$TMPDIR" PATH="$TMPDIR/bin:/usr/bin:/bin" "$REPO_ROOT/scripts/update-visual-explainer.sh" > "$TMPDIR/out"

test -L "$TMPDIR/.agents/skills/visual-explainer"
test "$(readlink "$TMPDIR/.agents/skills/visual-explainer")" = "../../Projects/visual-explainer/plugins/visual-explainer"
test ! -e "$TMPDIR/.codex/visual-explainer"
test ! -e "$TMPDIR/.codex/skills"
test ! -e "$TMPDIR/.codex/prompts"
test ! -e "$TMPDIR/.claude"
grep -Fx -- "-C $TMPDIR/Projects/visual-explainer pull --ff-only" "$TMPDIR/git-args.log" >/dev/null
grep -F "removed stale $TMPDIR/.codex/visual-explainer" "$TMPDIR/out" >/dev/null
grep -F "visual-explainer -> $TMPDIR/.agents/skills/visual-explainer -> ../../Projects/visual-explainer/plugins/visual-explainer" "$TMPDIR/out" >/dev/null
