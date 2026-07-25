#!/usr/bin/env bash

COPY_OWNER=repo-skills
DESTINATION_KIND=
DESTINATION_REASON=
topology_tree_readable() ( # directory
  local file
  cd "$1" || return 1
  while IFS= read -r -d '' file; do
    [ -r "$file" ] || return 1
  done < <(find . -type f -not -path '*/.*' -print0 2>/dev/null)
)

topology_compute_copy_hash() { # directory
  local directory="$1" hasher file
  [ -d "$directory" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    hasher=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hasher=(shasum -a 256)
  else
    return 1
  fi
  (
    cd "$directory" || exit 1
    find . -type f -not -path '*/.*' -print0 |
      LC_ALL=C sort -z |
      while IFS= read -r -d '' file; do
        printf '%s\0' "$file"
        "${hasher[@]}" "$file" | cut -d' ' -f1 | tr -d '\n'
        printf '\0'
      done |
      "${hasher[@]}" | cut -d' ' -f1
  )
}

DESTINATION_MESSAGE=

topology_inspect_destination() { # source_id skill destination
  local source_id="$1" skill="$2" destination="$3"
  local installed expected marker_source marker_owner stored_hash recorded source_hash installed_hash
  DESTINATION_KIND=
  DESTINATION_REASON=
  DESTINATION_MESSAGE=

  if [ "$destination" = claude ] && [ "${TOPOLOGY_CLAUDE_ROOT_LEGACY:-0}" = 1 ]; then
    DESTINATION_KIND=absent
    return 0
  fi

  installed="$(repo_owned_destination_path "$REPO_ROOT" "$HOME" "$destination" "$skill")"
  if [ ! -e "$installed" ]; then
    DESTINATION_KIND=absent
    return 0
  fi
  expected="$(repo_owned_source_path "$REPO_ROOT" "$source_id" "$skill")"
  marker_source="$(sed -n '1p' "$installed/.agent-scripts-copy" 2>/dev/null || true)"
  marker_owner="$(sed -n '2p' "$installed/.agent-scripts-copy" 2>/dev/null || true)"
  if [ "$marker_owner" != "$COPY_OWNER" ]; then
    DESTINATION_KIND=foreign
    [ -n "$marker_owner" ] && DESTINATION_REASON=other-owner || DESTINATION_REASON=unowned
    return 0
  fi
  case "$marker_source" in
    /*) recorded="$marker_source" ;;
    *) recorded="$REPO_ROOT/$marker_source" ;;
  esac
  recorded="$(repo_owned_canonical_path "$recorded")"
  expected="$(repo_owned_canonical_path "$expected")"
  if [ "$recorded" != "$expected" ]; then
    DESTINATION_KIND=managed
    DESTINATION_REASON=source-mismatch
    return 0
  fi
  stored_hash="$(sed -n '3p' "$installed/.agent-scripts-copy" 2>/dev/null || true)"
  if [ -z "$stored_hash" ]; then
    DESTINATION_KIND=managed
    DESTINATION_REASON=unstamped
    return 0
  fi
  if ! topology_tree_readable "$expected" || ! topology_tree_readable "$installed" \
    || ! source_hash="$(topology_compute_copy_hash "$expected" 2>/dev/null)" \
    || ! installed_hash="$(topology_compute_copy_hash "$installed" 2>/dev/null)"; then
    DESTINATION_KIND=verification-failed
    DESTINATION_MESSAGE="cannot verify $source_id/$skill on $destination: copy content could not be read"
    return 0
  fi
  DESTINATION_KIND=managed
  if [ "$stored_hash" != "$source_hash" ] || [ "$stored_hash" != "$installed_hash" ]; then
    DESTINATION_REASON=content-mismatch
  fi
}

topology_list_retired_copies() {
  local surface entry marker_owner
  surface="$HOME/.agents/skills"
  [ -d "$surface" ] || return 0
  shopt -s nullglob
  for entry in "$surface"/*; do
    [ -d "$entry" ] || continue
    topology_is_name "${entry##*/}" || continue
    marker_owner="$(sed -n '2p' "$entry/.agent-scripts-copy" 2>/dev/null || true)"
    [ "$marker_owner" = "$COPY_OWNER" ] && printf '%s\n' "${entry##*/}"
  done
  shopt -u nullglob
}
