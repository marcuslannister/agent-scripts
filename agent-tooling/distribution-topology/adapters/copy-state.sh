#!/usr/bin/env bash

copy_state_canonical_path() {
  local candidate="$1"
  local directory base
  if [ -d "$candidate" ]; then
    (cd "$candidate" && pwd -P)
    return
  fi
  directory="$(dirname "$candidate")"
  base="$(basename "$candidate")"
  if [ -d "$directory" ]; then
    (cd "$directory" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$candidate"
  fi
}

refresh_source_clone() { # clone_dir repo_url
  local clone_dir="$1"
  local repo_url="$2"
  # Adapter stdout is the source-inventory protocol.
  if [ -d "$clone_dir/.git" ]; then
    git -C "$clone_dir" pull --ff-only >/dev/null
  else
    mkdir -p "$(dirname "$clone_dir")"
    git clone --depth 1 "$repo_url" "$clone_dir" >/dev/null
  fi
}

copy_contents_match() { # source destination
  local source="$1"
  local destination="$2"
  [ -d "$source" ] && [ -d "$destination" ] \
    && diff -qr -x .agent-scripts-copy -x .agent-scripts-copy-source \
      "$source" "$destination" >/dev/null 2>&1
}

inspect_copy_state() { # content_source marker_source destination owner repo_root
  local content_source="$1"
  local marker_source="$2"
  local destination="$3"
  local owner="$4"
  local repo_root="$5"
  local marker="$destination/.agent-scripts-copy"
  local marker_owner recorded_source expected_source stored_hash source_hash copy_hash

  if [ -L "$destination" ]; then
    if [ "$(copy_state_canonical_path "$destination")" = "$(copy_state_canonical_path "$marker_source")" ]; then
      printf 'drift\tlegacy-copy\n'
    else
      printf 'foreign\tunowned\n'
    fi
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

  if [ -f "$marker" ]; then
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    if [ -n "$marker_owner" ] && [ "$marker_owner" != "$owner" ]; then
      printf 'foreign\tother-owner\n'
      return
    fi
    recorded_source="$(sed -n '1p' "$marker" 2>/dev/null || true)"
    case "$recorded_source" in
      /*) ;;
      *) recorded_source="$repo_root/$recorded_source" ;;
    esac
    expected_source="$(copy_state_canonical_path "$marker_source")"
    recorded_source="$(copy_state_canonical_path "$recorded_source")"
    if [ "$recorded_source" != "$expected_source" ]; then
      if [ -n "$marker_owner" ]; then
        printf 'drift\tsource-mismatch\n'
      else
        printf 'foreign\tunowned\n'
      fi
      return
    fi
    stored_hash="$(sed -n '3p' "$marker" 2>/dev/null || true)"
    if [ -z "$marker_owner" ]; then
      if copy_contents_match "$content_source" "$destination"; then
        printf 'drift\tunstamped\n'
      else
        printf 'foreign\tunowned\n'
      fi
      return
    fi
    if [ -z "$stored_hash" ]; then
      printf 'drift\tunstamped\n'
      return
    fi
    if ! source_hash="$(compute_copy_hash "$content_source" 2>/dev/null)" || [ -z "$source_hash" ]; then
      printf 'error\tunreadable-source\n'
      return
    fi
    if ! copy_hash="$(compute_copy_hash "$destination" 2>/dev/null)" || [ -z "$copy_hash" ]; then
      printf 'error\tunreadable-copy\n'
      return
    fi
    if [ "$stored_hash" != "$source_hash" ] || [ "$stored_hash" != "$copy_hash" ]; then
      printf 'drift\tcontent-mismatch\n'
      return
    fi
    printf 'present\tmanaged\n'
    return
  fi

  if [ -f "$destination/.agent-scripts-copy-source" ]; then
    recorded_source="$(sed -n '1p' "$destination/.agent-scripts-copy-source" 2>/dev/null || true)"
    case "$recorded_source" in
      /*) ;;
      *) recorded_source="$repo_root/$recorded_source" ;;
    esac
    if [ "$(copy_state_canonical_path "$recorded_source")" = "$(copy_state_canonical_path "$marker_source")" ] \
      && copy_contents_match "$content_source" "$destination"; then
      printf 'drift\tunstamped\n'
    else
      printf 'foreign\tunowned\n'
    fi
  elif copy_contents_match "$content_source" "$destination" \
    || [ -z "$(find "$destination" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]; then
    printf 'drift\tunstamped\n'
  else
    printf 'foreign\tunowned\n'
  fi
}

install_staged_surface_copy() { # staging_root skill surface destination owner repo_root
  local staging_root="$1" skill="$2" surface="$3" destination="$4" owner="$5" repo_root="$6"
  local state detail
  IFS=$'\t' read -r state detail < <(
    inspect_copy_state "$staging_root/$skill" "$staging_root/$skill" \
      "$surface/$skill" "$owner" "$repo_root"
  )
  if [ "$state" = foreign ] || [ "$state" = error ]; then
    printf 'refusing unsafe copy adoption: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2
    return 1
  fi
  install_skill_copy "$staging_root/$skill" "$surface/$skill" "$owner" \
    "$staging_root/$skill" >/dev/null
}

ensure_staged_skill() { # skill; caller supplies inspect_stage_state/install_staged_skill
  local skill="$1" state detail
  IFS=$'\t' read -r state detail < <(inspect_stage_state "$skill")
  if [ "$state" = foreign ] || [ "$state" = error ]; then
    printf 'refusing unsafe staging adoption: %s (%s)\n' "$skill" "$detail" >&2
    return 1
  fi
  [ "$state" = present ] || install_staged_skill "$skill"
}

refresh_owned_staged_surface_copy() { # plan staging_root skill surface destination owner
  local plan="$1" staging_root="$2" skill="$3" surface="$4" destination="$5" owner="$6"
  local marker_owner
  if awk -F '\t' -v skill="$skill" -v destination="$destination" \
    '$1 == "remove" && $2 == skill && $3 == destination { found = 1 } END { exit !found }' "$plan"; then
    return 0
  fi
  marker_owner="$(sed -n '2p' "$surface/$skill/.agent-scripts-copy" 2>/dev/null || true)"
  [ "$marker_owner" = "$owner" ] || return 0
  install_skill_copy "$staging_root/$skill" "$surface/$skill" "$owner" \
    "$staging_root/$skill" >/dev/null
  printf 'installed\t%s\t%s\n' "$skill" "$destination"
}

# Markerless tracked staging: content only, no per-skill copy markers.
# Provenance lives in other-skills/<owner>/.source.json.

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
    rsync -a --delete "${src}/" "${dst}/" || return 1
  else
    rm -rf "$dst" || return 1
    mkdir -p "$dst" || return 1
    cp -R "${src}/." "${dst}/" || return 1
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

clear_staging_gitignore() { # repo_root owner
  local repo_root="$1"
  local owner="$2"
  local gitignore="$repo_root/.gitignore"
  [ -f "$gitignore" ] || return 0
  remove_gitignore_block "$gitignore" "$owner"
}
