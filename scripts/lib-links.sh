#!/usr/bin/env bash

# Shared link installers for update scripts.

link_warn() {
  printf '\033[0;31m!!!\033[0m %s\n' "$*" >&2
}

install_tracked_repo_symlink() {
  local repo_root="$1"
  local link="$2"
  local target="$3"
  local repo_path="${link#"$repo_root"/}"
  local index_target

  if [ "$repo_path" = "$link" ]; then
    link_warn "link is outside repo: $link"
    return 1
  fi

  index_target="$(git -C "$repo_root" cat-file -p ":$repo_path" 2>/dev/null || true)"
  if [ "$index_target" != "$target" ]; then
    link_warn "tracked symlink target mismatch: $repo_path"
    return 1
  fi

  git -C "$repo_root" checkout-index -f -- "$repo_path"
}

copy_external_skill_fallback() {
  local source_dir="$1"
  local target="$2"
  local link="$3"
  local marker="$link/.agent-scripts-copy-source"

  if [ -f "$marker" ]; then
    if [ "$(cat "$marker")" != "$target" ]; then
      link_warn "fallback copy target mismatch: $link"
      return 1
    fi
  elif [ -f "$source_dir/SKILL.md" ] && [ -f "$link/SKILL.md" ] && cmp -s "$source_dir/SKILL.md" "$link/SKILL.md"; then
    : # Adopt fallback copies created before the marker existed.
  else
    link_warn "existing directory is not an agent-scripts fallback copy: $link"
    return 1
  fi

  cp -R "${source_dir}/." "$link/" || return 1
  printf '%s\n' "$target" > "$marker" || return 1
  return 2
}

install_external_skill_link() {
  local source_dir="$1"
  local target="$2"
  local link="$3"
  local link_dir
  local link_name

  if [ -d "$link" ] && [ ! -L "$link" ]; then
    copy_external_skill_fallback "$source_dir" "$target" "$link"
    return $?
  fi

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    link_warn "not a directory or symlink, refusing to replace: $link"
    return 1
  fi

  link_dir="$(dirname "$link")"
  link_name="$(basename "$link")"
  if [ -L "$link" ]; then
    unlink "$link" || return 1
  fi
  if (cd "$link_dir" && ln -s "$target" "$link_name") 2>/dev/null && [ -L "$link" ]; then
    return 0
  fi

  if [ -d "$link" ] && [ ! -L "$link" ]; then
    copy_external_skill_fallback "$source_dir" "$target" "$link"
    return $?
  fi

  mkdir -p "$link" || return 1
  cp -R "${source_dir}/." "$link/" || return 1
  printf '%s\n' "$target" > "$link/.agent-scripts-copy-source" || return 1
  return 2
}
