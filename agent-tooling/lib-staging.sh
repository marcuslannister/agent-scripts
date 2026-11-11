#!/usr/bin/env bash

# Shared helpers for tracked foreign-skill staging (other-skills/<owner>/) and
# the machine-local source clone cache. Staging is markerless tracked content:
# provenance lives in git history plus each source dir's .source.json, never in
# per-skill copy markers (ADR-0005). Callers must source lib-copies.sh first
# for copy_warn and remove_gitignore_block.

# --- Source clone cache -----------------------------------------------------
# One shallow clone of a read-only upstream repository per source, refreshed in
# place. Per-machine state git never carries; holds no local edits, so any
# refresh failure discards the directory and clones again. Check mode must not
# use it — a preview clones into its own discovery root instead (a --check run
# writes nothing under HOME).

source_cache_dir() { # home source_id
  printf '%s/.cache/agent-scripts/source-clones/%s' "$1" "$2"
}

refresh_cached_clone() { # cache_dir repo_url
  local cache_dir="$1"
  local repo_url="$2"
  if [ -d "$cache_dir/.git" ] \
    && [ "$(git -C "$cache_dir" remote get-url origin 2>/dev/null)" = "$repo_url" ] \
    && git -C "$cache_dir" pull --ff-only --quiet >/dev/null 2>&1; then
    return 0
  fi
  rm -rf -- "$cache_dir"
  mkdir -p -- "$(dirname "$cache_dir")"
  git clone --depth 1 --quiet "$repo_url" "$cache_dir"
}

# --- Staging trees ----------------------------------------------------------

copy_contents_match() { # source destination
  local source="$1"
  local destination="$2"
  [ -d "$source" ] && [ -d "$destination" ] \
    && diff -qr -x .agent-scripts-copy -x .agent-scripts-copy-source -x .git \
      "$source" "$destination" >/dev/null 2>&1
}

install_stage_tree() { # source_dir dest_dir
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    copy_warn "missing source: $src"
    return 1
  fi
  if [ -L "$dst" ]; then
    unlink "$dst" || return 1
  elif [ -e "$dst" ] && [ ! -d "$dst" ]; then
    copy_warn "not a directory or symlink, refusing to replace: $dst"
    return 1
  fi
  mkdir -p "$dst" || return 1
  if [ "${AGENT_SCRIPTS_DISABLE_RSYNC:-0}" != "1" ] && command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --delete-excluded --exclude='.git' "${src}/" "${dst}/" || return 1
  else
    # Git Bash on Windows ships no rsync; emulate --delete with a fresh copy.
    rm -rf "$dst" || return 1
    mkdir -p "$dst" || return 1
    cp -R "${src}/." "${dst}/" || return 1
    rm -rf "${dst:?}/.git"
  fi
  rm -f "${dst}/.agent-scripts-copy" "${dst}/.agent-scripts-copy-source"
}

inspect_stage_tree() { # content_source destination
  local content_source="$1"
  local destination="$2"

  if [ -L "$destination" ]; then
    printf 'foreign\tunowned\n'
    return
  fi
  if [ ! -e "$destination" ]; then
    printf 'absent\tmissing\n'
    return
  fi
  if [ ! -d "$destination" ]; then
    printf 'foreign\tunowned\n'
    return
  fi
  if [ -f "$destination/.agent-scripts-copy" ] || [ -f "$destination/.agent-scripts-copy-source" ]; then
    printf 'drift\tlegacy-marker\n'
    return
  fi
  if copy_contents_match "$content_source" "$destination"; then
    printf 'present\tmanaged\n'
  else
    printf 'drift\tcontent-mismatch\n'
  fi
}

write_staging_source_json() { # staging_root repo clone_dir
  local staging_root="$1"
  local repo="$2"
  local clone_dir="$3"
  local commit synced_at

  commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$commit" ]; then
    printf 'unable to read upstream commit: %s\n' "$clone_dir" >&2
    return 1
  fi
  synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$staging_root" || return 1
  jq -n --arg repo "$repo" --arg commit "$commit" --arg syncedAt "$synced_at" \
    '{repo:$repo, commit:$commit, syncedAt:$syncedAt}' > "$staging_root/.source.json"
}

# --- Well-known skill sources -----------------------------------------------
# A site that publishes <origin>/.well-known/agent-skills/index.json instead of
# a git repo (agent-skills discovery RFC 0.2.0). Each entry lands in
# dest_root/<name>/ shaped like a flat clone, so the normal inventory and
# staging steps apply. Failures print one reason on stderr. Fetched scripts are
# staged, never run.
#   skill-md  SKILL.md checked against its digest, plus every references/,
#             scripts/ or assets/ file that a fetched .md names. The RFC wants
#             an archive for supporting files, but a site may serve them loose.
#   archive   .tar.gz or .zip checked against its digest, then unpacked.
# shortcut: loose files carry no digest, and archive size limits are checked
# after unpacking; upgrade when the index covers loose files or a hostile site
# matters.

sha256_of() { # file
  { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1
}

well_known_get() { # url output
  curl -fsSL --max-time 60 --max-filesize 10485760 \
    --proto '=https,file' --proto-redir '=https' -o "$2" "$1"
}

# Fetch every references/ scripts/ assets/ path that a .md under skill_dir
# names, until no new path appears. Segments start with a letter, digit, "_" or
# "-", so a path can never begin with "." or climb out of skill_dir.
fetch_well_known_loose_files() { # skill_url skill_dir
  local base="${1%/*}" skill_dir="$2" ref found count=0
  local pattern='(?:^|[\s(`"\x27\[])((?:references|scripts|assets)(?:/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)+)'

  while :; do
    found=0
    while IFS= read -r ref; do
      [ -e "$skill_dir/$ref" ] && continue
      count=$((count + 1))
      [ "$count" -le 200 ] || { echo "more than 200 files linked from $1" >&2; return 1; }
      mkdir -p "$(dirname "$skill_dir/$ref")" || return 1
      well_known_get "$base/$ref" "$skill_dir/$ref" \
        || { echo "cannot fetch $base/$ref" >&2; return 1; }
      found=1
    done < <(rg -I -o -r '$1' --glob '*.md' "$pattern" "$skill_dir" | LC_ALL=C sort -u)
    [ "$found" -eq 1 ] || return 0
  done
}

# Unpack a digest-verified archive into skill_dir. Rejects absolute or ".."
# paths, any symlink or hard link, a missing root SKILL.md, and a large result.
unpack_well_known_archive() { # archive skill_dir url
  local archive="$1" skill_dir="$2" url="$3" unpack="$2.unpack"

  mkdir -p "$unpack" || return 1
  { tar -tf "$archive" 2>/dev/null || unzip -Z1 "$archive" 2>/dev/null; } > "$archive.names" \
    || { echo "cannot read archive $url" >&2; return 1; }
  if rg -q '(^|/)\.\.(/|$)|^/|^[A-Za-z]:' "$archive.names"; then
    echo "unsafe path in archive $url" >&2
    return 1
  fi
  { tar -xf "$archive" -C "$unpack" 2>/dev/null || unzip -q "$archive" -d "$unpack"; } \
    || { echo "cannot unpack archive $url" >&2; return 1; }
  if [ -n "$(find "$unpack" \( -type l -o \( -type f -links +1 \) \) -print)" ]; then
    echo "archive $url contains links" >&2
    return 1
  fi
  [ -f "$unpack/SKILL.md" ] || { echo "archive $url has no SKILL.md at its root" >&2; return 1; }
  if [ "$(find "$unpack" -type f | wc -l)" -gt 1000 ] || [ "$(du -sk "$unpack" | cut -f1)" -gt 25600 ]; then
    echo "archive $url unpacks to more than 1000 files or 25 MiB" >&2
    return 1
  fi
  mv "$unpack" "$skill_dir"
}

fetch_well_known_skills() { # origin dest_root
  local origin="${1%/}" dest="$2" index="$2/.index.json"
  local name type url digest skill_url artifact

  mkdir -p "$dest" || return 1
  well_known_get "$origin/.well-known/agent-skills/index.json" "$index" \
    || { echo "cannot fetch $origin/.well-known/agent-skills/index.json" >&2; return 1; }
  jq -e '.skills | type == "array" and length > 0' "$index" >/dev/null \
    || { echo "index lists no skills" >&2; return 1; }

  while IFS=$'\t' read -r name type url digest; do
    case "$name" in ''|*[!a-z0-9-]*) echo "invalid skill name: $name" >&2; return 1 ;; esac
    case "$type" in skill-md|archive) ;; *) echo "unsupported entry type for $name: $type" >&2; return 1 ;; esac
    case "$digest" in sha256:*) ;; *) echo "missing sha256 digest for $name" >&2; return 1 ;; esac
    case "$url" in
      *://*) skill_url="$url" ;;
      /*) skill_url="$origin$url" ;;
      *) skill_url="$origin/.well-known/agent-skills/$url" ;;
    esac

    artifact="$dest/.artifact-$name"
    well_known_get "$skill_url" "$artifact" \
      || { echo "cannot fetch $skill_url" >&2; return 1; }
    [ "sha256:$(sha256_of "$artifact")" = "$digest" ] \
      || { echo "digest mismatch for $name" >&2; return 1; }

    case "$type" in
      skill-md)
        mkdir -p "$dest/$name" && mv "$artifact" "$dest/$name/SKILL.md" \
          && fetch_well_known_loose_files "$skill_url" "$dest/$name" || return 1 ;;
      archive)
        unpack_well_known_archive "$artifact" "$dest/$name" "$skill_url" || return 1 ;;
    esac
  done < <(jq -r '.skills[] | [.name, .type, .url, .digest] | @tsv' "$index")
}

write_well_known_source_json() { # staging_root origin fetch_root
  local staging_root="$1" origin="$2" fetch_root="$3"

  mkdir -p "$staging_root" || return 1
  jq --arg origin "$origin" --arg syncedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{repo:$origin, digests:(.skills | map({(.name): .digest}) | add), syncedAt:$syncedAt}' \
    "$fetch_root/.index.json" > "$staging_root/.source.json"
}

clear_staging_gitignore() { # repo_root owner
  local repo_root="$1"
  local owner="$2"
  local gitignore="$repo_root/.gitignore"
  [ -f "$gitignore" ] || return 0
  remove_gitignore_block "$gitignore" "$owner"
}
