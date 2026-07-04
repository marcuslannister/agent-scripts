#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/Projects/visual-explainer/.git" "$TMPDIR/Projects/visual-explainer/plugins/visual-explainer/commands"
printf '%s\n' '---' 'name: visual-explainer' 'description: "test"' '---' > "$TMPDIR/Projects/visual-explainer/plugins/visual-explainer/SKILL.md"
mkdir -p "$TMPDIR/.codex"
ln -s "../Projects/visual-explainer/plugins/visual-explainer" "$TMPDIR/.codex/visual-explainer"
if [ ! -L "$TMPDIR/.codex/visual-explainer" ]; then
  rm -rf "$TMPDIR/.codex/visual-explainer"
  printf '%s\n' "../Projects/visual-explainer/plugins/visual-explainer" > "$TMPDIR/.codex/visual-explainer"
fi
cat > "$TMPDIR/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/git-args.log"
exit 0
EOF
chmod +x "$TMPDIR/bin/git"

HOME="$TMPDIR" PATH="$TMPDIR/bin:/usr/bin:/bin" "$REPO_ROOT/scripts/update-visual-explainer.sh" > "$TMPDIR/out"

if [ -L "$TMPDIR/.agents/skills/visual-explainer" ]; then
  test "$(readlink "$TMPDIR/.agents/skills/visual-explainer")" = "../../Projects/visual-explainer/plugins/visual-explainer"
  grep -F "visual-explainer -> $TMPDIR/.agents/skills/visual-explainer -> ../../Projects/visual-explainer/plugins/visual-explainer" "$TMPDIR/out" >/dev/null
else
  test -d "$TMPDIR/.agents/skills/visual-explainer/commands"
  test "$(cat "$TMPDIR/.agents/skills/visual-explainer/.agent-scripts-copy-source")" = "../../Projects/visual-explainer/plugins/visual-explainer"
  grep -F "visual-explainer -> $TMPDIR/.agents/skills/visual-explainer (copied from $TMPDIR/Projects/visual-explainer/plugins/visual-explainer; symlink unavailable)" "$TMPDIR/out" >/dev/null
fi
test ! -e "$TMPDIR/.codex/visual-explainer"
test ! -e "$TMPDIR/.codex/skills"
test ! -e "$TMPDIR/.codex/prompts"
test ! -e "$TMPDIR/.claude"
grep -Fx -- "-C $TMPDIR/Projects/visual-explainer pull --ff-only" "$TMPDIR/git-args.log" >/dev/null
grep -F "removed stale $TMPDIR/.codex/visual-explainer" "$TMPDIR/out" >/dev/null
