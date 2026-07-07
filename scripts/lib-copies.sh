#!/usr/bin/env bash

# Shared copy installers for update scripts.
# Skills from source-only clones are rsynced into a surface as COPIES — never
# symlinks. Copies landing in the repo's skills/ dir stay untracked via a
# marker-delimited .gitignore block regenerated on every run.
# Each copy carries a .agent-scripts-copy marker: line 1 is the upstream source
# path, line 2 is the owner — the id of the updater that owns the copy — and
# line 3 is the copy's content hash at sync time (best-effort; omitted when no
# sha256 tool is available). Orphan cleanup keys on the owner, so two updaters
# can share one surface (and one source_root) without knowing anything about
# each other; the hash lets check_skill_copy_updates spot upstream changes and
# local edits without a full re-sync. All marker readers are line-addressed, so
# older two-line markers stay valid.

copy_warn() {
  printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2
}

copy_info() {
  printf '\033[0;32m==>\033[0m %s\n' "$*"
}

# Deterministic SHA-256 over a skill dir's non-hidden files. Hidden entries
# (including the .agent-scripts-copy marker itself) are excluded, so a copy's
# digest is stable whether or not it carries a marker. Emits the digest on
# stdout; returns non-zero (and nothing usable) when no sha256 tool exists, so
# callers can degrade gracefully rather than abort.
compute_copy_hash() { # dir
  local dir="$1"
  [ -d "$dir" ] || { copy_warn "hash: not a directory: $dir"; return 1; }

  local hasher
  if command -v sha256sum >/dev/null 2>&1; then
    hasher="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hasher="shasum -a 256"
  else
    copy_warn "no sha256 tool (sha256sum/shasum) available"
    return 1
  fi

  # Feed "relpath\0<per-file sha>\0" for every non-hidden file, path-sorted in
  # the C locale, into one final hash. Byte-sorting keeps the digest identical
  # across machines and rsync runs.
  ( cd "$dir" || exit 1
    find . -type f -not -path '*/.*' -print0 \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' f; do
          printf '%s\0' "$f"
          $hasher "$f" | cut -d' ' -f1 | tr -d '\n'
          printf '\0'
        done \
      | $hasher | cut -d' ' -f1
  )
}

install_skill_copy() { # source_dir dest_dir owner
  local src="$1"
  local dst="$2"
  local owner="$3"
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
  elif [ -d "$dst" ] && [ ! -f "$marker" ]; then
    # Adopt copies older updaters generated: lib-links.sh fallback copies
    # carried .agent-scripts-copy-source; pre-marker rsync copies match their
    # upstream SKILL.md. Anything else non-empty is treated as user-owned.
    if [ -f "${dst}/.agent-scripts-copy-source" ]; then
      : # legacy fallback copy; the sync below replaces its marker with ours
    elif [ -f "${src}/SKILL.md" ] && [ -f "${dst}/SKILL.md" ] \
      && cmp -s "${src}/SKILL.md" "${dst}/SKILL.md"; then
      : # matches upstream; pre-marker generated copy
    elif [ -n "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]; then
      copy_warn "existing directory is not an agent-scripts copy, refusing to overwrite: $dst (delete it if an older updater generated it)"
      return 1
    fi
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
    printf '%s\n%s\n%s\n' "$src" "$owner" "$hash" > "$marker" || return 1
  else
    printf '%s\n%s\n' "$src" "$owner" > "$marker" || return 1
  fi
}

cleanup_marked_skill_copies() { # surface owner keep_name...
  local surface="$1"
  local owner="$2"
  shift 2
  local marker marker_owner name keep keep_name failed=0

  if [ "$#" -eq 0 ]; then
    copy_warn "no current copy names for owner ${owner}; refusing orphan cleanup under ${surface}"
    return 1
  fi

  [ -d "$surface" ] || return 0
  for marker in "$surface"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker")"
    # Legacy single-line markers predate ownership. When several updaters share
    # one surface their legacy copies are indistinguishable, so never delete an
    # unowned copy — it gets an owner line the next time its own updater syncs
    # it (install_skill_copy always writes one).
    [ -n "$marker_owner" ] || continue
    [ "$marker_owner" = "$owner" ] || continue

    name="$(basename "$(dirname "$marker")")"
    keep=0
    for keep_name in "$@"; do
      if [ "$name" = "$keep_name" ]; then
        keep=1
        break
      fi
    done
    [ "$keep" -eq 0 ] || continue

    if rm -rf "${surface:?}/${name}"; then
      copy_info "removed orphaned copy: ${name}"
    else
      failed=1
    fi
  done
  return "$failed"
}

regen_gitignore_block() { # gitignore_path marker generator entry...
  local gitignore="$1"
  local marker="$2"
  local generator="$3"
  shift 3
  local block="# ${marker} start (generated by ${generator})"$'\n'
  local entry

  for entry in "$@"; do
    block="${block}${entry}"$'\n'
  done
  block="${block}# ${marker} end"

  touch "$gitignore"
  # An unterminated block would make the sed range below eat everything down
  # to EOF, including other blocks and hand-written rules.
  if grep -q "^# ${marker} start" "$gitignore" \
    && ! grep -q "^# ${marker} end$" "$gitignore"; then
    copy_warn "unterminated '# ${marker}' block in ${gitignore}; fix it by hand, not rewriting"
    return 1
  fi
  sed "/^# ${marker} start/,/^# ${marker} end$/d" "$gitignore" > "${gitignore}.tmp"
  printf '%s\n' "$block" >> "${gitignore}.tmp"
  mv "${gitignore}.tmp" "$gitignore"
}

sync_skill_copies() { # owner source_root dest_surface gitignore|"" name...
  local owner="$1"
  local source_root="$2"
  local surface="$3"
  local gitignore="$4"
  shift 4
  local name failed=0
  local names=("$@")
  local ignore_entries=()

  if [ "${#names[@]}" -eq 0 ]; then
    copy_warn "no skill names given to sync_skill_copies for owner ${owner}"
    return 1
  fi

  mkdir -p "$surface" || return 1
  for name in "${names[@]}"; do
    if [ ! -f "${source_root}/${name}/SKILL.md" ]; then
      copy_warn "missing source skill: ${source_root}/${name}"
      failed=1
    elif ! install_skill_copy "${source_root}/${name}" "${surface}/${name}" "$owner"; then
      failed=1
    else
      copy_info "skill copied -> ${surface}/${name}"
    fi
    # Keep ignoring an existing copy even when this run's sync failed, so a
    # transient failure can't surface third-party files as trackable. The entry
    # is relative to the .gitignore dir, which sits one level above the surface.
    if [ -d "${surface}/${name}" ]; then
      ignore_entries+=("$(basename "$surface")/${name}")
    fi
  done

  # Orphan cleanup keys on the owner, so copies other updaters own in this same
  # surface are left untouched — no cross-block reading needed.
  if ! cleanup_marked_skill_copies "$surface" "$owner" "${names[@]}"; then
    failed=1
  fi

  if [ -n "$gitignore" ]; then
    if ! regen_gitignore_block "$gitignore" "$owner" "sync_skill_copies" \
      ${ignore_entries[@]+"${ignore_entries[@]}"}; then
      failed=1
    fi
  fi

  return "$failed"
}

# Read-only drift check for owner's copies under a surface. For each name it
# compares the marker's stored hash (line 3, from the last sync) against both
# the current upstream source and the on-disk copy:
#   stored != source  -> upstream advanced since last sync (update available)
#   stored != copy     -> the copy was hand-edited since install (local drift)
# Reports per skill; returns non-zero if anything is out of date, tampered, or
# unverifiable — so it doubles as a scriptable "is a sync needed?" gate. Never
# writes anything.
check_skill_copy_updates() { # source_root surface owner name...
  local source_root="$1"
  local surface="$2"
  local owner="$3"
  shift 3
  local name marker stored src_hash copy_hash status=0

  if [ "$#" -eq 0 ]; then
    copy_warn "no skill names given to check_skill_copy_updates for owner ${owner}"
    return 1
  fi

  for name in "$@"; do
    marker="${surface}/${name}/.agent-scripts-copy"
    if [ ! -f "$marker" ]; then
      copy_warn "missing   ${name}: no copy under ${surface} (run sync)"
      status=1
      continue
    fi
    stored="$(sed -n '3p' "$marker")"
    if [ -z "$stored" ]; then
      copy_warn "unstamped ${name}: legacy marker has no hash; re-sync to stamp it"
      status=1
      continue
    fi

    if ! src_hash="$(compute_copy_hash "${source_root}/${name}")" || [ -z "$src_hash" ]; then
      copy_warn "unreadable ${name}: cannot hash source ${source_root}/${name}"
      status=1
      continue
    fi
    if ! copy_hash="$(compute_copy_hash "${surface}/${name}")" || [ -z "$copy_hash" ]; then
      copy_warn "unreadable ${name}: cannot hash copy ${surface}/${name}"
      status=1
      continue
    fi

    if [ "$stored" != "$src_hash" ]; then
      copy_info "UPDATE    ${name}: upstream changed since last sync"
      status=1
    fi
    if [ "$stored" != "$copy_hash" ]; then
      copy_warn "TAMPER    ${name}: local copy edited since install"
      status=1
    fi
    if [ "$stored" = "$src_hash" ] && [ "$stored" = "$copy_hash" ]; then
      copy_info "ok        ${name}"
    fi
  done

  return "$status"
}
