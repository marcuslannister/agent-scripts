#!/usr/bin/env bash
set -euo pipefail

action="${1:?action required}"
home="${2:?home required}"
codex_dir="$home/.codex"
legacy_root="$codex_dir/skills"

encode() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

entry_kind() { # path
  if [ -L "$1" ]; then
    printf 'symlink\n'
  elif [ -d "$1" ]; then
    printf 'directory\n'
  elif [ -f "$1" ]; then
    printf 'file\n'
  else
    printf 'other\n'
  fi
}

list_drift() {
  local entry name kind
  local entries=()

  if [ -L "$legacy_root" ]; then
    printf 'entry\t%s\troot-symlink\n' "$(encode skills)"
    return 0
  fi
  if [ -e "$legacy_root" ] && [ ! -d "$legacy_root" ]; then
    printf 'entry\t%s\troot-file\n' "$(encode skills)"
    return 0
  fi
  [ -d "$legacy_root" ] || return 0

  shopt -s dotglob nullglob
  entries=("$legacy_root"/*)
  shopt -u dotglob nullglob
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    [ "$name" = .system ] && continue
    kind="$(entry_kind "$entry")"
    printf 'entry\t%s\t%s\n' "$(encode "$name")" "$kind"
  done
}

make_backup_dir() {
  local stamp base candidate suffix
  stamp="${AGENT_SCRIPTS_MIGRATION_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  base="$codex_dir/skills-migrated-$stamp"
  candidate="$base"
  suffix=1
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    candidate="$base-$suffix"
    suffix=$((suffix + 1))
  done
  mkdir -p "$codex_dir"
  mkdir "$candidate"
  printf '%s\n' "$candidate"
}

verify_clean() {
  local drift
  drift="$(list_drift)"
  if [ -n "$drift" ]; then
    while IFS=$'\t' read -r _ encoded kind; do
      printf 'legacy Codex root still has unmigrated %s entry (hex name: %s)\n' "$kind" "$encoded" >&2
    done <<< "$drift"
    return 1
  fi
}

reconcile() {
  local backup entry name kind destination failed
  local entries=()
  failed=0

  if [ -L "$legacy_root" ] || { [ -e "$legacy_root" ] && [ ! -d "$legacy_root" ]; }; then
    kind=root-symlink
    [ -L "$legacy_root" ] || kind=root-file
    if ! backup="$(make_backup_dir)"; then
      printf 'could not create Codex-root migration backup under %s; legacy root preserved\n' "$codex_dir" >&2
      return 1
    fi
    destination="$backup/skills"
    if mv "$legacy_root" "$destination"; then
      if ! mkdir -p "$legacy_root"; then
        printf 'migrated legacy Codex root to %s but could not recreate %s\n' "$destination" "$legacy_root" >&2
        return 1
      fi
      printf 'migrated\t%s\t%s\t%s\n' "$(encode skills)" "$kind" "$(encode "$destination")"
    else
      printf 'could not migrate legacy Codex root %s; preserved in place\n' "$legacy_root" >&2
      return 1
    fi
    verify_clean
    return
  fi

  [ -d "$legacy_root" ] || return 0
  shopt -s dotglob nullglob
  entries=("$legacy_root"/*)
  shopt -u dotglob nullglob
  for entry in "${entries[@]}"; do
    [ "${entry##*/}" = .system ] && continue
    if [ -z "${backup:-}" ]; then
      if ! backup="$(make_backup_dir)"; then
        printf 'could not create Codex-root migration backup under %s; legacy entries preserved\n' "$codex_dir" >&2
        return 1
      fi
    fi
    name="${entry##*/}"
    kind="$(entry_kind "$entry")"
    destination="$backup/$name"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      printf 'Codex-root backup destination already exists; preserving %s\n' "$entry" >&2
      failed=1
      continue
    fi
    if mv "$entry" "$destination"; then
      printf 'migrated\t%s\t%s\t%s\n' "$(encode "$name")" "$kind" "$(encode "$destination")"
    else
      printf 'could not migrate legacy Codex-root entry %s; preserved in place\n' "$entry" >&2
      failed=1
    fi
  done

  verify_clean || failed=1
  [ "$failed" -eq 0 ]
}

case "$action" in
  inspect) list_drift ;;
  reconcile) reconcile ;;
  verify) verify_clean ;;
  *) printf 'unknown Codex-root hygiene action: %s\n' "$action" >&2; exit 2 ;;
esac
