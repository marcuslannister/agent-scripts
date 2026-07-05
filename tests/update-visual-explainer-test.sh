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
# Legacy symlink from the pre-copy era must be replaced by a real copy.
mkdir -p "$TMPDIR/.agents/skills"
ln -s "../../Projects/visual-explainer/plugins/visual-explainer" "$TMPDIR/.agents/skills/visual-explainer" 2>/dev/null || true
cat > "$TMPDIR/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/git-args.log"
exit 0
EOF
chmod +x "$TMPDIR/bin/git"

HOME="$TMPDIR" PATH="$TMPDIR/bin:/usr/bin:/bin" "$REPO_ROOT/scripts/update-visual-explainer.sh" > "$TMPDIR/out"

test ! -L "$TMPDIR/.agents/skills/visual-explainer"
test -d "$TMPDIR/.agents/skills/visual-explainer/commands"
test -f "$TMPDIR/.agents/skills/visual-explainer/SKILL.md"
grep -F "visual-explainer copied -> $TMPDIR/.agents/skills/visual-explainer" "$TMPDIR/out" >/dev/null
test ! -e "$TMPDIR/.codex/visual-explainer"
test ! -e "$TMPDIR/.codex/skills"
test ! -e "$TMPDIR/.codex/prompts"
test ! -e "$TMPDIR/.claude"
grep -Fx -- "-C $TMPDIR/Projects/visual-explainer pull --ff-only" "$TMPDIR/git-args.log" >/dev/null
grep -F "removed stale $TMPDIR/.codex/visual-explainer" "$TMPDIR/out" >/dev/null
