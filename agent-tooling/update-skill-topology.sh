#!/usr/bin/env bash
set -uo pipefail

# Acquire phase (ADR-0009): refresh cached upstream source clones and mirror
# each skill-bearing source's complete inventory into tracked staging under
# other-skills/<owner>/. Selection-blind — never reads the skills matrix — and
# performs no native plugin operations; plugins are user-managed per-machine
# state refreshed best-effort by update-plugins.sh. Check mode writes nothing
# under HOME: it clones into its own work root instead of the source cache.

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_PATH="$SCRIPT_DIR/sources.json"
MODE=reconcile
JSON_OUTPUT=0
TOPOLOGY_ERROR_MESSAGE=
TOPOLOGY_ERROR_CODE=0
TOPOLOGY_LOCK_PATH=
TOPOLOGY_RECOVERED_PID=
TOPOLOGY_RECOVERED_PENDING=0

source "$SCRIPT_DIR/lib-copies.sh"
source "$SCRIPT_DIR/lib-staging.sh"
source "$SCRIPT_DIR/distribution-topology/lock.sh"

topology_fail() {
  TOPOLOGY_ERROR_CODE="$1"
  TOPOLOGY_ERROR_MESSAGE="$2"
}

usage() {
  cat <<'EOF'
Usage: update-skill-topology.sh [--check] [--json]

Refresh upstream skill sources and mirror their complete inventories into
tracked other-skills/<owner>/ staging. Selection-blind: the skills matrix is
never read, and native plugins are never touched (ADR-0009).

Options:
  --check  Preview staging drift without writes (also never writes under HOME).
  --json   Write one JSON result document.
  -h, --help
           Show this help.

Exit codes:
  0   reconciled or check clean
  1   drift or acquire failure
  2   invalid usage or sources list
  130 interrupted
EOF
}

for argument in "$@"; do
  case "$argument" in
    --check) MODE=check ;;
    --json) JSON_OUTPUT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'invalid argument: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
  esac
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-scripts-acquire-XXXXXX")"
trap 'topology_release_lock; rm -rf -- "$WORK_ROOT"' EXIT
trap 'topology_release_lock; rm -rf -- "$WORK_ROOT"; exit 130' INT TERM

SOURCES_TSV="$WORK_ROOT/sources.tsv"
DRIFT_TSV="$WORK_ROOT/drift.tsv"
CHANGES_TSV="$WORK_ROOT/changes.tsv"
ERRORS="$WORK_ROOT/errors.txt"
WARNINGS="$WORK_ROOT/warnings.txt"
: > "$SOURCES_TSV"
: > "$DRIFT_TSV"
: > "$CHANGES_TSV"
: > "$ERRORS"
: > "$WARNINGS"

append_error()   { printf '%s\n' "$1" >> "$ERRORS"; }
append_warning() { printf '%s\n' "$1" >> "$WARNINGS"; }

emit_document() {
  local status="$1"
  jq -n \
    --arg mode "$MODE" \
    --arg status "$status" \
    --rawfile sources "$SOURCES_TSV" \
    --rawfile drift "$DRIFT_TSV" \
    --rawfile changes "$CHANGES_TSV" \
    --rawfile errors "$ERRORS" \
    --rawfile warnings "$WARNINGS" '
      def lines($value): $value | split("\n") | map(select(length > 0));
      {
        schemaVersion: 2,
        mode: $mode,
        status: $status,
        sources: (lines($sources) | map(split("\t") |
          {id:.[0],classification:.[1],inventoryCount:(.[2]|tonumber),result:.[3]})),
        drift: (lines($drift) | map(split("\t") |
          {sourceId:.[0],skill:.[1],reason:.[2],action:.[3]})),
        changes: (lines($changes) | map(split("\t") |
          {sourceId:.[0],skill:.[1],action:.[2]})),
        errors: lines($errors),
        warnings: (lines($warnings) | map({message:.}))
      }
    '
}

write_result() {
  local status="$1" document="$WORK_ROOT/document.json"
  emit_document "$status" > "$document"
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    cat "$document"
    return
  fi
  printf 'Skill acquire %s: %s\n' "$MODE" "$status"
  jq -r '.drift[] | "- \(.action) \(.skill) in staging (\(.reason))"' "$document"
  jq -r '.changes[] | "- \(.action) \(.skill) in \(.sourceId) staging"' "$document"
  jq -r '.warnings[] | "warning: \(.message)"' "$document" >&2
  jq -r '.errors[] | "error: \(.)"' "$document" >&2
}

if ! topology_acquire_lock; then
  append_error "$TOPOLOGY_ERROR_MESSAGE"
  write_result failed
  exit "${TOPOLOGY_ERROR_CODE:-1}"
fi
if [ -n "$TOPOLOGY_RECOVERED_PID" ]; then
  append_warning "recovered stale topology lock held by PID $TOPOLOGY_RECOVERED_PID"
elif [ "$TOPOLOGY_RECOVERED_PENDING" -eq 1 ]; then
  append_warning 'recovered stale topology lock with no recorded PID'
fi

if [ ! -f "$SOURCES_PATH" ]; then
  append_error 'sources list is missing: agent-tooling/sources.json'
  write_result failed
  exit 2
fi
if ! jq -e '
    .version == 2 and
    (.sources | type == "array" and length > 0) and
    ([.sources[].id] | length) == ([.sources[].id] | unique | length) and
    all(.sources[];
      (.id | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.classification == "source-only" or .classification == "npx-only" or
       .classification == "plugin-claude-only" or .classification == "dual-plugin") and
      (.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
      ((has("staging") | not) or
        ((.staging | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
         (.discovery == "flat" or .discovery == "recursive") and
         has("subroot"))) and
      ((has("plugin") | not) or
        ((.plugin.name | type) == "string" and
         (.plugin.marketplaces | type) == "object" and
         ((.plugin | has("codexUpgrade") | not) or .plugin.codexUpgrade == "manual"))))
  ' "$SOURCES_PATH" >/dev/null 2>&1; then
  append_error 'invalid sources list: agent-tooling/sources.json'
  write_result invalid
  exit 2
fi

valid_skill_name() {
  case "$1" in ''|*[!a-z0-9-]*) return 1 ;; *) return 0 ;; esac
}

source_field() { # source_id jq_suffix
  jq -r --arg id "$1" ".sources[] | select(.id == \$id) | $2" "$SOURCES_PATH"
}

# --- Per-source staging reconciliation --------------------------------------
acquire_source() { # source_id
  local source_id="$1"
  local repo subroot staging discovery classification repo_url clone_dir source_root
  local inventory="$WORK_ROOT/$source_id.inventory.tsv"
  local skill_file skill relative state detail count=0 source_failed=0
  local staging_root action planned

  classification="$(source_field "$source_id" '.classification')"
  repo="$(source_field "$source_id" '.repo')"
  subroot="$(source_field "$source_id" '.subroot')"
  staging="$(source_field "$source_id" '.staging')"
  discovery="$(source_field "$source_id" '.discovery')"
  staging_root="$REPO_ROOT/other-skills/$staging"
  repo_url="https://github.com/$repo.git"

  if [ "$MODE" = check ]; then
    clone_dir="$WORK_ROOT/clones/$source_id"
    if [ ! -d "$clone_dir/.git" ]; then
      if ! git clone --depth 1 --quiet "$repo_url" "$clone_dir" 2>>"$WORK_ROOT/$source_id.clone.err"; then
        append_error "source $source_id clone failed: $repo_url"
        record_source "$source_id" "$classification" 0 failed
        return
      fi
    fi
  else
    clone_dir="$(source_cache_dir "$HOME" "$source_id")"
    if ! refresh_cached_clone "$clone_dir" "$repo_url" 2>>"$WORK_ROOT/$source_id.clone.err"; then
      append_error "source $source_id clone refresh failed: $repo_url"
      record_source "$source_id" "$classification" 0 failed
      return
    fi
  fi
  source_root="$clone_dir"
  [ -n "$subroot" ] && source_root="$clone_dir/$subroot"
  if [ ! -d "$source_root" ]; then
    append_error "source $source_id inventory root missing: $source_root"
    record_source "$source_id" "$classification" 0 failed
    return
  fi

  # Inventory: skill name -> source dir. Upstream mirror precedence: a name
  # tracked as skills/<name>/SKILL.md stays owned by the repo mirror.
  : > "$inventory"
  while IFS= read -r skill_file; do
    [ -f "$skill_file" ] || continue
    skill="$(basename "$(dirname "$skill_file")")"
    if ! valid_skill_name "$skill"; then
      append_error "source $source_id returned an invalid inventory skill: $skill"
      source_failed=1
      continue
    fi
    if git -C "$REPO_ROOT" ls-files --error-unmatch -- "skills/$skill/SKILL.md" >/dev/null 2>&1; then
      continue
    fi
    printf '%s\t%s\n' "$skill" "$(dirname "$skill_file")" >> "$inventory"
    count=$((count + 1))
  done < <(
    if [ "$discovery" = recursive ]; then
      find "$source_root" -name SKILL.md -type f 2>/dev/null | LC_ALL=C sort
    else
      for skill_file in "$source_root"/*/SKILL.md; do printf '%s\n' "$skill_file"; done
    fi
  )
  if [ "$count" -eq 0 ] && [ "$source_failed" -eq 0 ]; then
    append_error "source $source_id inventory is empty"
    record_source "$source_id" "$classification" 0 failed
    return
  fi
  if [ "$(cut -f1 "$inventory" | LC_ALL=C sort -u | wc -l | tr -d ' ')" != "$count" ]; then
    append_error "source $source_id inventory contains duplicate skill names"
    record_source "$source_id" "$classification" "$count" failed
    return
  fi

  # Staged skills present or refreshed; orphans removed.
  while IFS=$'\t' read -r skill relative; do
    IFS=$'\t' read -r state detail < <(inspect_stage_tree "$relative" "$staging_root/$skill")
    case "$state" in
      present) ;;
      absent|drift)
        # A missing skill is an install; one whose content moved is an update.
        # Check and reconcile must name the same operation.
        action=updated
        planned=update
        if [ "$state" = absent ]; then
          action=installed
          planned=install
        fi
        if [ "$MODE" = check ]; then
          printf '%s\t%s\t%s\t%s\n' "$source_id" "$skill" "$detail" "$planned" >> "$DRIFT_TSV"
        elif install_stage_tree "$relative" "$staging_root/$skill" >/dev/null; then
          printf '%s\t%s\t%s\n' "$source_id" "$skill" "$action" >> "$CHANGES_TSV"
        else
          append_error "source $source_id failed to stage $skill"
          source_failed=1
        fi
        ;;
      *)
        append_error "source $source_id refusing unsafe staging adoption: $skill ($detail)"
        source_failed=1
        ;;
    esac
  done < "$inventory"

  if [ -d "$staging_root" ]; then
    for skill_file in "$staging_root"/*/SKILL.md; do
      [ -f "$skill_file" ] || continue
      skill="$(basename "$(dirname "$skill_file")")"
      awk -F '\t' -v skill="$skill" '$1 == skill { found = 1 } END { exit !found }' "$inventory" && continue
      if [ "$MODE" = check ]; then
        printf '%s\t%s\torphan\tremove\n' "$source_id" "$skill" >> "$DRIFT_TSV"
      elif rm -rf -- "${staging_root:?}/$skill"; then
        printf '%s\t%s\tremoved\n' "$source_id" "$skill" >> "$CHANGES_TSV"
      else
        append_error "source $source_id failed to remove orphaned staged skill: $skill"
        source_failed=1
      fi
    done
  fi

  if [ "$MODE" != check ]; then
    clear_staging_gitignore "$REPO_ROOT" "$source_id" || source_failed=1
    clear_staging_gitignore "$REPO_ROOT" "$staging" || source_failed=1
    if ! write_staging_source_json "$staging_root" "$repo_url" "$clone_dir"; then
      append_error "source $source_id could not record staging provenance"
      source_failed=1
    fi
  fi

  local result=clean
  if [ "$source_failed" -eq 1 ]; then
    result=failed
  elif awk -F '\t' -v id="$source_id" '$1 == id { found = 1 } END { exit !found }' "$CHANGES_TSV"; then
    result=changed
  elif awk -F '\t' -v id="$source_id" '$1 == id { found = 1 } END { exit !found }' "$DRIFT_TSV"; then
    result=drift
  fi
  record_source "$source_id" "$classification" "$count" "$result"
}

record_source() { # id classification count result
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$SOURCES_TSV"
}

shopt -s nullglob
while IFS= read -r source_id; do
  acquire_source "$source_id"
done < <(jq -r '.sources[] | select(has("staging")) | .id' "$SOURCES_PATH" | LC_ALL=C sort)
shopt -u nullglob

if [ -s "$ERRORS" ]; then
  result_status=failed
  result_code=1
elif [ "$MODE" = check ] && [ -s "$DRIFT_TSV" ]; then
  result_status=drift
  result_code=1
elif [ "$MODE" = check ]; then
  result_status=clean
  result_code=0
else
  result_status=reconciled
  result_code=0
fi
write_result "$result_status"
exit "$result_code"
