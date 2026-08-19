#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

. "$REPO_ROOT/agent-tooling/lib-copies.sh"

marker_source() { sed -n '1p' "$1"; }  # line 1 = upstream source path
marker_owner()  { sed -n '2p' "$1"; }   # line 2 = owning updater id
marker_hash()   { sed -n '3p' "$1"; }    # line 3 = content hash at sync time

mkdir -p "$TMPDIR/src/scripts"
printf '%s\n' '---' 'name: t' '---' > "$TMPDIR/src/SKILL.md"
printf 'x\n' > "$TMPDIR/src/scripts/run.sh"

# Fresh copy: creates dir, content, and an ownership marker whose line 3 is the
# content hash (equal to the copy's own hash right after an exact rsync).
install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/a" owner-a
test -f "$TMPDIR/dst/a/SKILL.md"
test -f "$TMPDIR/dst/a/scripts/run.sh"
test "$(marker_source "$TMPDIR/dst/a/.agent-scripts-copy")" = "$TMPDIR/src"
test "$(marker_owner "$TMPDIR/dst/a/.agent-scripts-copy")" = "owner-a"
test -n "$(marker_hash "$TMPDIR/dst/a/.agent-scripts-copy")"
test "$(marker_hash "$TMPDIR/dst/a/.agent-scripts-copy")" = "$(compute_copy_hash "$TMPDIR/dst/a")"

# compute_copy_hash: ignores the marker (hidden) and is stable across identical
# trees, but changes when tracked content changes.
H_BEFORE="$(compute_copy_hash "$TMPDIR/dst/a")"
printf 'note\n' > "$TMPDIR/dst/a/.agent-scripts-copy-extra"  # hidden -> ignored
test "$(compute_copy_hash "$TMPDIR/dst/a")" = "$H_BEFORE"
rm "$TMPDIR/dst/a/.agent-scripts-copy-extra"
printf 'changed\n' >> "$TMPDIR/dst/a/SKILL.md"                # tracked -> differs
test "$(compute_copy_hash "$TMPDIR/dst/a")" != "$H_BEFORE"

# Re-run over an owned copy: syncs deletions and keeps the two-line marker.
rm "$TMPDIR/src/scripts/run.sh"
install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/a" owner-a
test ! -e "$TMPDIR/dst/a/scripts/run.sh"
test "$(marker_owner "$TMPDIR/dst/a/.agent-scripts-copy")" = "owner-a"

# Legacy symlink destination: replaced by a real owned copy.
ln -s "$TMPDIR/src" "$TMPDIR/dst/b" 2>/dev/null || true
if [ -L "$TMPDIR/dst/b" ]; then
  install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/b" owner-b
  test ! -L "$TMPDIR/dst/b"
  test "$(marker_owner "$TMPDIR/dst/b/.agent-scripts-copy")" = "owner-b"
fi

# Legacy lib-links fallback copy (.agent-scripts-copy-source): adopted.
mkdir -p "$TMPDIR/dst/e"
printf 'old-target\n' > "$TMPDIR/dst/e/.agent-scripts-copy-source"
printf 'stale\n' > "$TMPDIR/dst/e/leftover.txt"
install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/e" owner-e
test "$(marker_owner "$TMPDIR/dst/e/.agent-scripts-copy")" = "owner-e"
test ! -e "$TMPDIR/dst/e/.agent-scripts-copy-source"
test ! -e "$TMPDIR/dst/e/leftover.txt"

# Pre-marker generated copy (SKILL.md matches upstream): adopted.
mkdir -p "$TMPDIR/dst/f"
cp "$TMPDIR/src/SKILL.md" "$TMPDIR/dst/f/SKILL.md"
printf 'stale\n' > "$TMPDIR/dst/f/leftover.txt"
install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/f" owner-f
test "$(marker_owner "$TMPDIR/dst/f/.agent-scripts-copy")" = "owner-f"
test ! -e "$TMPDIR/dst/f/leftover.txt"

# Marker-less dir whose SKILL.md differs from upstream: refused.
mkdir -p "$TMPDIR/dst/g"
printf 'my own skill\n' > "$TMPDIR/dst/g/SKILL.md"
if install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/g" owner-g 2>/dev/null; then
  echo "FAIL: overwrote a dir with a diverging SKILL.md" >&2
  exit 1
fi
test "$(cat "$TMPDIR/dst/g/SKILL.md")" = "my own skill"

# Non-owned, non-empty directory: refused, content untouched.
mkdir -p "$TMPDIR/dst/c"
printf 'user content\n' > "$TMPDIR/dst/c/mine.txt"
if install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/c" owner-c 2>/dev/null; then
  echo "FAIL: overwrote a non-owned directory" >&2
  exit 1
fi
test "$(cat "$TMPDIR/dst/c/mine.txt")" = "user content"
test ! -e "$TMPDIR/dst/c/SKILL.md"

# Plain file destination: refused.
printf 'f\n' > "$TMPDIR/dst/d"
if install_skill_copy "$TMPDIR/src" "$TMPDIR/dst/d" owner-d 2>/dev/null; then
  echo "FAIL: replaced a plain file" >&2
  exit 1
fi

# Block removal preserves trailing rules and refuses misordered markers.
RB="$TMPDIR/remove-block"
mkdir -p "$RB"
printf '%s\n' before '# owner start (generated)' ignored '# owner end' after > "$RB/valid"
remove_gitignore_block "$RB/valid" owner
printf '%s\n' before after | cmp -s - "$RB/valid"
printf '%s\n' before '# owner end' after '# owner start (generated)' trailing > "$RB/misordered"
cp "$RB/misordered" "$RB/expected"
if remove_gitignore_block "$RB/misordered" owner 2>/dev/null; then
  echo "FAIL: removed a misordered ignore block" >&2
  exit 1
fi
cmp -s "$RB/expected" "$RB/misordered"

echo "lib-copies tests passed"
