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
  if [ -d "$clone_dir/.git" ]; then
    git -C "$clone_dir" pull --ff-only
  else
    mkdir -p "$(dirname "$clone_dir")"
    git clone --depth 1 "$repo_url" "$clone_dir"
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

emit_copy_inspection() { # plan source_root marker_root surface destination owner repo_root
  local plan_path="$1"
  local source_root="$2"
  local marker_root="$3"
  local surface="$4"
  local destination="$5"
  local owner="$6"
  local repo_root="$7"
  local expected skill planned_destination state detail marker marker_owner orphan

  while IFS=$'\t' read -r expected skill planned_destination; do
    [ "$planned_destination" = "$destination" ] || continue
    IFS=$'\t' read -r state detail < <(
      inspect_copy_state "$source_root/$skill" "$marker_root/$skill" "$surface/$skill" "$owner" "$repo_root"
    )
    printf '%s\t%s\t%s\t%s\n' "$state" "$skill" "$destination" "$detail"
  done < "$plan_path"

  [ -d "$surface" ] || return 0
  for marker in "$surface"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    [ "$marker_owner" = "$owner" ] || continue
    orphan="$(basename "$(dirname "$marker")")"
    case "$orphan" in ''|*[!a-z0-9-]*) continue ;; esac
    if awk -F '\t' -v skill="$orphan" -v destination="$destination" \
      '$2 == skill && $3 == destination { found = 1 } END { exit !found }' "$plan_path"; then
      continue
    fi
    printf 'orphan\t%s\t%s\tmanaged\n' "$orphan" "$destination"
  done
}

reconcile_copy_actions() { # plan source_root marker_root surface destination owner repo_root
  local plan_path="$1"
  local source_root="$2"
  local marker_root="$3"
  local surface="$4"
  local destination="$5"
  local owner="$6"
  local repo_root="$7"
  local operation skill planned_destination marker marker_owner state detail failed=0

  while IFS=$'\t' read -r operation skill planned_destination; do
    [ "$planned_destination" = "$destination" ] || continue
    case "$skill" in ''|*[!a-z0-9-]*) printf 'invalid copy skill name: %s\n' "$skill" >&2; failed=1; continue ;; esac
    case "$operation" in
      install)
        IFS=$'\t' read -r state detail < <(
          inspect_copy_state "$source_root/$skill" "$marker_root/$skill" \
            "$surface/$skill" "$owner" "$repo_root"
        )
        if [ "$state" = foreign ] || [ "$state" = error ]; then
          printf 'refusing unsafe copy adoption: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2
          failed=1
        elif install_skill_copy "$source_root/$skill" "$surface/$skill" "$owner" >/dev/null; then
          printf 'installed\t%s\t%s\n' "$skill" "$destination"
        else
          failed=1
        fi
        ;;
      remove)
        marker="$surface/$skill/.agent-scripts-copy"
        marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
        if [ "$marker_owner" != "$owner" ]; then
          printf 'refusing to remove unowned copy: %s -> %s\n' "$skill" "$destination" >&2
          failed=1
        elif rm -rf -- "$surface/$skill"; then
          printf 'removed\t%s\t%s\n' "$skill" "$destination"
        else
          failed=1
        fi
        ;;
      *) printf 'unknown copy operation: %s\n' "$operation" >&2; failed=1 ;;
    esac
  done < "$plan_path"
  return "$failed"
}

verify_copy_states() { # plan source_root marker_root surface destination owner repo_root
  local plan_path="$1"
  local source_root="$2"
  local marker_root="$3"
  local surface="$4"
  local destination="$5"
  local owner="$6"
  local repo_root="$7"
  local expected skill planned_destination state detail failed=0

  while IFS=$'\t' read -r expected skill planned_destination; do
    [ "$planned_destination" = "$destination" ] || continue
    IFS=$'\t' read -r state detail < <(
      inspect_copy_state "$source_root/$skill" "$marker_root/$skill" "$surface/$skill" "$owner" "$repo_root"
    )
    case "$expected:$state" in
      present:present|absent:absent|absent:foreign) ;;
      *)
        printf 'managed copy verification failed: %s -> %s (%s)\n' "$skill" "$destination" "$detail" >&2
        failed=1
        ;;
    esac
  done < "$plan_path"
  return "$failed"
}

refresh_copy_gitignore() { # repo_root surface owner
  local repo_root="$1"
  local surface="$2"
  local owner="$3"
  local marker marker_owner name
  local entries=()

  if [ -d "$surface" ]; then
    for marker in "$surface"/*/.agent-scripts-copy; do
      [ -f "$marker" ] || continue
      marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
      [ "$marker_owner" = "$owner" ] || continue
      name="$(basename "$(dirname "$marker")")"
      entries+=("$(basename "$surface")/$name")
    done
  fi
  regen_gitignore_block "$repo_root/.gitignore" "$owner" update-skill-topology.sh \
    ${entries[@]+"${entries[@]}"}
}
