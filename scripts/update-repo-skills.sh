#!/usr/bin/env bash
set -euo pipefail

# Sync the repo's tracked skills into ~/.agents/skills as COPIES.
# Root policy: each CLI reads exactly one skills root — Claude Code reads
# skills/ (via ~/.claude/skills), Codex reads only ~/.agents/skills. The
# old ~/.codex/skills symlink is gone: it made Codex load the shared repo
# root too and see every skill present in both roots twice. Legacy entries
# under ~/.codex/skills are migrated into a timestamped backup so Codex keeps
# exactly one active skills surface. Third-party copies in skills/ are
# untracked and already canonical in ~/.agents/skills, so only tracked skills
# flow this way. Re-runnable; exits non-zero on failure.

info()    { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
section() { printf '\n\033[1;33m>>> %s\033[0m\n' "$*"; }
warn()    { printf '\033[0;31m!!!\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-copies.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
AGENTS_SKILLS_DIR="${HOME}/.agents/skills"

fail=0

make_migration_backup_dir() { # codex_dir
  local codex_dir="$1"
  local stamp="${AGENT_SCRIPTS_MIGRATION_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  local base="${codex_dir}/skills-migrated-${stamp}"
  local candidate="$base"
  local suffix=1

  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    candidate="${base}-${suffix}"
    suffix=$((suffix + 1))
  done
  mkdir -p "$codex_dir" || return 1
  mkdir "$candidate" || return 1
  printf '%s\n' "$candidate"
}

migrate_legacy_codex_skills() { # codex_skills
  local codex_skills="$1"
  local codex_dir backup_dir entry name
  local migrated=0
  local blocked=0
  local entries=()

  codex_dir="$(dirname "$codex_skills")"

  if [ -L "$codex_skills" ] || { [ -e "$codex_skills" ] && [ ! -d "$codex_skills" ]; }; then
    if ! backup_dir="$(make_migration_backup_dir "$codex_dir")"; then
      warn "could not create migration backup under ${codex_dir}; legacy ${codex_skills} preserved in place"
      return 1
    fi
    if mv "$codex_skills" "${backup_dir}/skills"; then
      mkdir -p "$codex_skills" || {
        warn "migrated legacy ${codex_skills} -> ${backup_dir}/skills, but could not recreate ${codex_skills}"
        return 1
      }
      info "migrated legacy ${codex_skills} -> ${backup_dir}/skills"
      return 0
    fi
    warn "could not migrate legacy ${codex_skills}; preserved in place"
    return 1
  fi

  [ -d "$codex_skills" ] || return 0

  while IFS= read -r -d '' entry; do
    entries+=("$entry")
  done < <(find "$codex_skills" -mindepth 1 -maxdepth 1 ! -name '.system' -print0 2>/dev/null)
  [ "${#entries[@]}" -eq 0 ] && return 0

  if ! backup_dir="$(make_migration_backup_dir "$codex_dir")"; then
    warn "could not create migration backup under ${codex_dir}; legacy entries preserved in place"
    return 1
  fi

  for entry in "${entries[@]}"; do
    name="$(basename "$entry")"
    if [ -e "${backup_dir}/${name}" ] || [ -L "${backup_dir}/${name}" ]; then
      warn "backup destination already exists, preserving legacy entry in place: ${entry}"
      blocked=1
      continue
    fi
    if mv "$entry" "${backup_dir}/${name}"; then
      migrated=$((migrated + 1))
    else
      warn "could not migrate legacy ${codex_skills} entry: ${entry}; preserved in place"
      blocked=1
    fi
  done

  [ "$migrated" -eq 0 ] || info "migrated ${migrated} legacy ${codex_skills} entries -> ${backup_dir}"
  [ "$blocked" -eq 0 ] || return 1
}

verify_one_root_codex_surface() { # codex_skills tracked_names
  local codex_skills="$1"
  local tracked_names="$2"
  local entry name marker marker_source
  local verified=0
  local failed=0

  if [ -L "$codex_skills" ] || { [ -e "$codex_skills" ] && [ ! -d "$codex_skills" ]; }; then
    warn "legacy Codex skills root is still active and not a directory: ${codex_skills}"
    failed=1
  elif [ -d "$codex_skills" ]; then
    while IFS= read -r -d '' entry; do
      warn "legacy Codex skills root still has non-system entry: ${entry}"
      failed=1
    done < <(find "$codex_skills" -mindepth 1 -maxdepth 1 ! -name '.system' -print0 2>/dev/null)
  fi

  for name in $tracked_names; do
    marker="${AGENTS_SKILLS_DIR}/${name}/.agent-scripts-copy"
    if [ ! -f "${AGENTS_SKILLS_DIR}/${name}/SKILL.md" ]; then
      warn "tracked skill missing from active Codex surface: ${AGENTS_SKILLS_DIR}/${name}"
      failed=1
      continue
    fi
    if [ ! -f "$marker" ]; then
      warn "tracked skill missing Codex surface marker: ${AGENTS_SKILLS_DIR}/${name}"
      failed=1
      continue
    fi
    marker_source="$(cat "$marker")"
    if [ "$marker_source" != "${SKILLS_DIR}/${name}" ]; then
      warn "tracked skill marker mismatch for ${name}: ${marker_source}"
      failed=1
      continue
    fi
    verified=$((verified + 1))
  done

  if [ "$failed" -eq 0 ]; then
    info "verified one-root Codex surface: ${codex_skills} has no non-system entries; ${verified} tracked marked copies active"
    return 0
  fi
  return 1
}

section "Repo skills → ~/.agents/skills (Codex surface)"

# Root-policy drift migration: non-system entries under ~/.codex/skills mean
# Codex double-loads. Move them into a timestamped backup, leaving only the
# Codex-managed .system dir behind when present. The active ~/.agents/skills
# surface is synced separately below and never overwritten with legacy drift.
codex_skills="${HOME}/.codex/skills"
if ! migrate_legacy_codex_skills "$codex_skills"; then
  fail=1
fi

tracked="$(git -C "$REPO_ROOT" ls-files 'skills/*/SKILL.md' | cut -d/ -f2 | sort -u)"
if [ -z "$tracked" ]; then
  warn "no tracked skills found under ${SKILLS_DIR}"
  exit 1
fi

mkdir -p "$AGENTS_SKILLS_DIR"
copied=0
for name in $tracked; do
  if install_skill_copy "${SKILLS_DIR}/${name}" "${AGENTS_SKILLS_DIR}/${name}"; then
    copied=$((copied + 1))
  else
    fail=1
  fi
done
info "copied ${copied} tracked skills into ${AGENTS_SKILLS_DIR}"

if ! cleanup_marked_skill_copies "$AGENTS_SKILLS_DIR" "$SKILLS_DIR" $tracked; then
  fail=1
fi

if ! verify_one_root_codex_surface "$codex_skills" "$tracked"; then
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
section "repo-skills done"
