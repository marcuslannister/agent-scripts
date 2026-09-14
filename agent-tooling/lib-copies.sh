#!/usr/bin/env bash

# Shared copy installers for update scripts.
# Skills from source-only / npx clones are rsynced into surfaces as COPIES —
# never symlinks. Foreign inventories stage under tracked other-skills/<owner>/
# without per-skill markers (see install_stage_tree / .source.json). Surface
# copies carry a .agent-scripts-copy marker: line 1 is the tracked-staging
# source path, line 2 is the owner — the id of the updater that owns the copy —
# and line 3 is the copy's content hash at sync time (best-effort; omitted when
# no sha256 tool is available). Orphan cleanup keys on the owner, so two
# updaters can share one surface without knowing anything about each other; the
# hash lets distribute.sh tell an advanced upstream from a hand-edited copy
# without a full re-sync. All marker readers are line-addressed, so older
# two-line markers stay valid.

copy_warn() {
  printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2
}

# Deterministic SHA-256 over a skill dir's non-hidden files. Hidden entries
# (including the .agent-scripts-copy marker itself) are excluded, so a copy's
# digest is stable whether or not it carries a marker. hash_copy_dirs prints
# "path<TAB>digest" per dir in one Python process; compute_copy_hash wraps it
# for a single dir. Returns non-zero when python3 is missing.
hash_copy_dirs() { # dirs...
  local out list
  list="$(mktemp "${TMPDIR:-/tmp}/hash-copy-dirs.XXXXXX")" || return 1
  printf '%s\n' "$@" > "$list"
  # Paths go through a list file, not argv: MSYS Python rewrites /c/foo to C:/foo.
  if command -v python3 >/dev/null 2>&1; then
    if out="$(python3 - "$list" <<'PY'
import hashlib, os, subprocess, sys

def hash_dir(root):
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if name.startswith("."):
                continue
            full = os.path.join(dirpath, name)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            entries.append(("./" + rel, full))
    entries.sort(key=lambda item: item[0].encode("utf-8"))
    outer = hashlib.sha256()
    for rel, full in entries:
        digest = hashlib.sha256()
        with open(full, "rb") as fh:
            digest.update(fh.read())
        outer.update(rel.encode("utf-8") + b"\0" + digest.hexdigest().encode("ascii") + b"\0")
    return outer.hexdigest()

list_path = sys.argv[1]
with open(list_path, encoding="utf-8") as fh:
    bash_paths = [line.rstrip("\n\r") for line in fh if line.rstrip("\n\r")]
try:
    converted = subprocess.check_output(["cygpath", "-w", "-f", list_path], text=True)
    win_paths = [line.rstrip("\n") for line in converted.splitlines()]
    if len(win_paths) != len(bash_paths):
        win_paths = bash_paths
except (FileNotFoundError, OSError, subprocess.CalledProcessError):
    win_paths = bash_paths
for bash, win in zip(bash_paths, win_paths):
    root = win if os.path.isdir(win) else bash
    if os.path.isdir(root):
        sys.stdout.buffer.write((bash + "\t" + hash_dir(root) + "\n").encode())
PY
)" && { [ -n "$out" ] || [ "$#" -eq 0 ]; }; then
      rm -f "$list"
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
  fi
  rm -f "$list"
  copy_warn "no sha256 tool (python3) available"
  return 1
}

compute_copy_hash() { # dir
  local dir="$1" line digest
  [ -d "$dir" ] || { copy_warn "hash: not a directory: $dir"; return 1; }
  line="$(hash_copy_dirs "$dir")" || return 1
  line="${line%$'\r'}"
  digest="${line##*$'\t'}"
  [ -n "$digest" ] || return 1
  printf '%s\n' "$digest"
}

# Can an unmarked destination directory be taken over by a marked copy without
# losing anything? True for copies older updaters generated: lib-links.sh
# fallback copies carried .agent-scripts-copy-source; pre-marker rsync copies
# match their upstream SKILL.md. An empty directory has nothing to lose either.
# Anything else is user-owned and must be preserved. Callers that plan surface
# work consult this before install_skill_copy so the plan and the install agree
# on which directories are adoptable.
copy_is_adoptable() { # source_dir dest_dir
  local src="$1" dst="$2"
  [ -f "${dst}/.agent-scripts-copy-source" ] && return 0
  [ -f "${src}/SKILL.md" ] && [ -f "${dst}/SKILL.md" ] \
    && cmp -s "${src}/SKILL.md" "${dst}/SKILL.md" && return 0
  [ -z "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]
}

install_skill_copy() { # source_dir dest_dir owner [marker_source]
  local src="$1"
  local dst="$2"
  local owner="$3"
  local marker_source="${4:-$src}"
  local marker="${dst}/.agent-scripts-copy"

  if [ ! -d "$src" ]; then
    copy_warn "missing source: $src"
    return 1
  fi
  # Legacy state from the symlink era; replace with a real copy.
  if [ -L "$dst" ]; then
    unlink "$dst" || return 1
  elif [ -e "$dst" ] && [ ! -d "$dst" ]; then
    copy_warn "not a directory or symlink, refusing to replace: $dst"
    return 1
  elif [ -d "$dst" ] && [ ! -f "$marker" ] && ! copy_is_adoptable "$src" "$dst"; then
    copy_warn "existing directory is not an agent-scripts copy, refusing to overwrite: $dst (delete it if an older updater generated it)"
    return 1
  fi
  mkdir -p "$dst" || return 1
  if [ "${AGENT_SCRIPTS_DISABLE_RSYNC:-0}" != "1" ] && command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${src}/" "${dst}/" || return 1
  else
    # Git Bash on Windows ships no rsync; emulate --delete with a fresh copy.
    rm -rf "$dst" || return 1
    mkdir -p "$dst" || return 1
    cp -R "${src}/." "${dst}/" || return 1
  fi
  # Marker line 3 is the copy's content hash at sync time; it lets an updater
  # later tell "upstream advanced" from "this copy was hand-edited" without a
  # full re-sync. Hashing is best-effort: if no sha256 tool exists we still
  # write a valid two-line marker rather than fail the install.
  local hash
  if hash="$(compute_copy_hash "$src")" && [ -n "$hash" ]; then
    printf '%s\n%s\n%s\n' "$marker_source" "$owner" "$hash" > "$marker" || return 1
  else
    printf '%s\n%s\n' "$marker_source" "$owner" > "$marker" || return 1
  fi
}

remove_gitignore_block() { # gitignore_path marker
  local gitignore="$1"
  local marker="$2"
  local start_count end_count start_line end_line

  start_count="$(grep -c "^# ${marker} start" "$gitignore" || true)"
  end_count="$(grep -c "^# ${marker} end$" "$gitignore" || true)"
  [ "$start_count" -ne 0 ] || [ "$end_count" -ne 0 ] || return 0
  if [ "$start_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    copy_warn "invalid '# ${marker}' block in ${gitignore}; fix it by hand, not rewriting"
    return 1
  fi
  start_line="$(grep -n "^# ${marker} start" "$gitignore" | cut -d: -f1)"
  end_line="$(grep -n "^# ${marker} end$" "$gitignore" | cut -d: -f1)"
  if [ "$start_line" -ge "$end_line" ]; then
    copy_warn "misordered '# ${marker}' block in ${gitignore}; fix it by hand, not rewriting"
    return 1
  fi
  sed "${start_line},${end_line}d" "$gitignore" > "${gitignore}.tmp"
  mv "${gitignore}.tmp" "$gitignore"
}
