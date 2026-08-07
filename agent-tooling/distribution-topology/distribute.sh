#!/usr/bin/env bash
set -uo pipefail

MODULE_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$MODULE_DIR/../.." && pwd)"
MATRIX_PATH="$REPO_ROOT/agent-tooling/skills-matrix.md"
OWNER=skill-matrix
MODE=reconcile
JSON_OUTPUT=0
TOPOLOGY_ERROR_MESSAGE=
TOPOLOGY_ERROR_CODE=0
TOPOLOGY_LOCK_PATH=
TOPOLOGY_RECOVERED_PID=
TOPOLOGY_RECOVERED_PENDING=0

source "$REPO_ROOT/agent-tooling/lib-copies.sh"
source "$MODULE_DIR/lock.sh"

topology_fail() {
  TOPOLOGY_ERROR_CODE="$1"
  TOPOLOGY_ERROR_MESSAGE="$2"
}

usage() {
  cat <<'EOF'
Usage: sync-skill-surfaces.sh [--check] [--json]

Reconcile matrix-selected skill copies to Claude and Codex surfaces using only
tracked repository content. The matrix Source column is informational.

Options:
  --check  Preview surface drift without writes.
  --json   Write one JSON result document.
  -h, --help
           Show this help.

Exit codes:
  0   reconciled or check clean
  1   drift or reconciliation failure
  2   invalid usage or matrix
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

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-scripts-distribute-XXXXXX")"
trap 'topology_release_lock; rm -rf -- "$WORK_ROOT"' EXIT INT TERM
PLAN_TSV="$WORK_ROOT/plan.tsv"
DRIFT_TSV="$WORK_ROOT/drift.tsv"
CHANGES_TSV="$WORK_ROOT/changes.tsv"
SKIPPED_TSV="$WORK_ROOT/skipped.tsv"
ERRORS="$WORK_ROOT/errors.txt"
WARNINGS="$WORK_ROOT/warnings.txt"
ROWS_TSV="$WORK_ROOT/rows.tsv"
MATRIX_INVALID=0
: > "$PLAN_TSV"
: > "$DRIFT_TSV"
: > "$CHANGES_TSV"
: > "$SKIPPED_TSV"
: > "$ERRORS"
: > "$WARNINGS"
: > "$ROWS_TSV"

append_error() {
  printf '%s\n' "$1" >> "$ERRORS"
}

append_warning() {
  printf '%s\n' "$1" >> "$WARNINGS"
}

append_matrix_error() {
  MATRIX_INVALID=1
  append_error "$1"
}

emit_document() {
  local status="$1"
  jq -n \
    --arg mode "$MODE" \
    --arg status "$status" \
    --rawfile plan "$PLAN_TSV" \
    --rawfile drift "$DRIFT_TSV" \
    --rawfile changes "$CHANGES_TSV" \
    --rawfile skipped "$SKIPPED_TSV" \
    --rawfile errors "$ERRORS" \
    --rawfile warnings "$WARNINGS" '
      def lines($value): $value | split("\n") | map(select(length > 0));
      def destinations($value): if $value == "" then [] else $value | split(",") end;
      def plan_rows:
        lines($plan) | map(split("\t") |
          {sourceId:.[0],skill:.[1],sourcePath:.[2],destinations:destinations(.[3])});
      def drift_rows:
        lines($drift) | map(split("\t") |
          {sourceId:.[0],skill:.[1],destination:.[2],reason:.[3],action:.[4]});
      def change_rows:
        lines($changes) | map(split("\t") |
          {sourceId:.[0],skill:.[1],destination:.[2],action:.[3]});
      def skipped_rows:
        lines($skipped) | map(split("\t") |
          {skill:.[0],destination:.[1],reason:.[2]});
      {
        schemaVersion: 1,
        mode: $mode,
        status: $status,
        plan: plan_rows,
        drift: drift_rows,
        changes: change_rows,
        skipped: skipped_rows,
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
  printf 'Skill surface %s: %s\n' "$MODE" "$status"
  jq -r '.drift[] | "- \(.action) \(.skill) on \(.destination) (\(.reason))"' "$document"
  jq -r '.changes[] | "- \(.action) \(.skill) on \(.destination)"' "$document"
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

if [ ! -f "$MATRIX_PATH" ]; then
  append_error 'skills matrix is missing: agent-tooling/skills-matrix.md'
  write_result failed
  exit 1
fi

awk -F '|' '
  function trim(value) {
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    return value
  }
  /^\|[[:space:]]*`/ {
    skill = trim($2)
    gsub(/^`|`$/, "", skill)
    type = trim($4)
    claude = trim($5)
    codex = trim($6)
    if (type == "skill") print skill "\t" claude "\t" codex
  }
' "$MATRIX_PATH" > "$ROWS_TSV"

if [ ! -s "$ROWS_TSV" ]; then
  append_matrix_error 'skills matrix contains no skill rows'
fi
while IFS=$'\t' read -r skill claude codex; do
  if [[ ! "$skill" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    append_matrix_error "invalid skill name in matrix: $skill"
  fi
  if { [ "$claude" != Y ] && [ "$claude" != N ]; } \
    || { [ "$codex" != Y ] && [ "$codex" != N ]; }; then
    append_matrix_error "invalid selection for matrix skill $skill: Claude=$claude Codex=$codex"
  fi
done < "$ROWS_TSV"
while IFS= read -r duplicate; do
  [ -n "$duplicate" ] && append_matrix_error "duplicate skill row in matrix: $duplicate"
done < <(cut -f1 "$ROWS_TSV" | sort | uniq -d)

if [ "$MATRIX_INVALID" -eq 1 ]; then
  write_result invalid
  exit 2
fi

CLAUDE_ROOT="$HOME/.claude/skills"
CODEX_ROOT="$HOME/.agents/skills"
roots_safe=1
for root in "$CLAUDE_ROOT" "$CODEX_ROOT"; do
  if [ -L "$root" ]; then
    append_error "refusing symlinked skill surface root: $root"
    roots_safe=0
  elif [ -e "$root" ] && [ ! -d "$root" ]; then
    append_error "skill surface root is not a directory: $root"
    roots_safe=0
  elif [ -d "$root" ]; then
    shopt -s nullglob
    for entry in "$root"/*; do
      if [ -L "$entry" ]; then
        append_error "refusing symlinked skill surface entry: $entry"
        roots_safe=0
      fi
    done
    shopt -u nullglob
  fi
done

resolve_skill() { # skill
  local skill="$1" candidate owner
  local candidates=()
  if [ -f "$REPO_ROOT/skills/$skill/SKILL.md" ]; then
    printf 'repo-claude\t%s\n' "$REPO_ROOT/skills/$skill"
    return 0
  fi
  if [ -f "$REPO_ROOT/codex-skills/$skill/SKILL.md" ]; then
    printf 'repo-codex\t%s\n' "$REPO_ROOT/codex-skills/$skill"
    return 0
  fi
  shopt -s nullglob
  candidates=("$REPO_ROOT"/other-skills/*/"$skill")
  shopt -u nullglob
  local valid=()
  for candidate in "${candidates[@]}"; do
    [ -f "$candidate/SKILL.md" ] && valid+=("$candidate")
  done
  if [ "${#valid[@]}" -eq 1 ]; then
    owner="$(basename "$(dirname "${valid[0]}")")"
    printf '%s\t%s\n' "$owner" "${valid[0]}"
    return 0
  fi
  if [ "${#valid[@]}" -gt 1 ]; then
    printf 'ambiguous skill %s resolves to: %s\n' "$skill" "${valid[*]}" >&2
    return 2
  fi
  return 1
}

CLAUDE_DESIRED="$WORK_ROOT/claude-desired.tsv"
CODEX_DESIRED="$WORK_ROOT/codex-desired.tsv"
CLAUDE_SELECTED="$WORK_ROOT/claude-selected.txt"
CODEX_SELECTED="$WORK_ROOT/codex-selected.txt"
: > "$CLAUDE_DESIRED"
: > "$CODEX_DESIRED"
: > "$CLAUDE_SELECTED"
: > "$CODEX_SELECTED"
while IFS=$'\t' read -r skill claude codex; do
  destinations=
  [ "$claude" = Y ] && destinations=claude
  if [ "$codex" = Y ]; then
    [ -n "$destinations" ] && destinations="$destinations,codex" || destinations=codex
  fi
  [ "$claude" = Y ] && printf '%s\n' "$skill" >> "$CLAUDE_SELECTED"
  [ "$codex" = Y ] && printf '%s\n' "$skill" >> "$CODEX_SELECTED"
  [ -n "$destinations" ] || {
    printf 'matrix\t%s\t\t\t\n' "$skill" >> "$PLAN_TSV"
    continue
  }
  resolution="$(resolve_skill "$skill" 2> "$WORK_ROOT/resolve.err")"
  resolve_code=$?
  if [ "$resolve_code" -ne 0 ]; then
    if [ "$resolve_code" -eq 2 ]; then
      append_error "$(cat "$WORK_ROOT/resolve.err")"
    else
      append_error "matrix selects $skill but no tracked source directory resolves it"
    fi
    printf 'unresolved\t%s\t\t%s\n' "$skill" "$destinations" >> "$PLAN_TSV"
    continue
  fi
  IFS=$'\t' read -r source_id source_path <<< "$resolution"
  printf '%s\t%s\t%s\t%s\n' "$source_id" "$skill" "$source_path" "$destinations" >> "$PLAN_TSV"
  [ "$claude" = Y ] && printf '%s\t%s\t%s\n' "$skill" "$source_id" "$source_path" >> "$CLAUDE_DESIRED"
  [ "$codex" = Y ] && printf '%s\t%s\t%s\n' "$skill" "$source_id" "$source_path" >> "$CODEX_DESIRED"
done < "$ROWS_TSV"

is_managed_owner() { # owner
  case "$1" in
    skill-matrix|repo-skills|anthropic-skills|khazix-skills|matt-skills|humanlayer-skills|visual-explainer|cli-skills) return 0 ;;
    *) return 1 ;;
  esac
}

copy_needs_refresh() { # source destination
  local source="$1" destination="$2" marker
  local recorded_source marker_owner stored_hash source_hash copy_hash
  marker="$destination/.agent-scripts-copy"
  [ -d "$destination" ] || return 1
  [ -f "$marker" ] || return 2
  recorded_source="$(sed -n '1p' "$marker" 2>/dev/null || true)"
  marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
  stored_hash="$(sed -n '3p' "$marker" 2>/dev/null || true)"
  is_managed_owner "$marker_owner" || return 3
  [ "$marker_owner" = "$OWNER" ] || return 1
  source_hash="$(compute_copy_hash "$source" 2>/dev/null || true)"
  copy_hash="$(compute_copy_hash "$destination" 2>/dev/null || true)"
  [ "$recorded_source" = "$source" ] \
    && [ -n "$stored_hash" ] \
    && [ "$stored_hash" = "$source_hash" ] \
    && [ "$stored_hash" = "$copy_hash" ]
}

is_skipped() { # skill destination
  local wanted_skill="$1" wanted_destination="$2" skill destination reason
  while IFS=$'\t' read -r skill destination reason; do
    [ "$skill" = "$wanted_skill" ] && [ "$destination" = "$wanted_destination" ] && return 0
  done < "$SKIPPED_TSV"
  return 1
}

has_drift() { # skill destination
  local wanted_skill="$1" wanted_destination="$2"
  local source_id skill destination reason action
  while IFS=$'\t' read -r source_id skill destination reason action; do
    [ "$skill" = "$wanted_skill" ] && [ "$destination" = "$wanted_destination" ] && return 0
  done < "$DRIFT_TSV"
  return 1
}

inspect_surface() { # destination root desired_tsv selected_names
  local destination="$1" root="$2" desired="$3" selected="$4"
  local skill source_id source_path target marker marker_owner name skipped_reason
  while IFS=$'\t' read -r skill source_id source_path; do
    [ -n "$skill" ] || continue
    target="$root/$skill"
    copy_needs_refresh "$source_path" "$target"
    refresh_code=$?
    if [ "$refresh_code" -eq 0 ]; then
      continue
    else
      case "$refresh_code" in
        2)
          # No marker. A pre-marker copy of this same skill has nothing worth
          # preserving, so plan an install and let install_skill_copy adopt it;
          # anything else on this path is the user's and stays put.
          if copy_is_adoptable "$source_path" "$target"; then
            printf '%s\t%s\t%s\tunmarked\tinstall\n' "$source_id" "$skill" "$destination" >> "$DRIFT_TSV"
          else
            append_error "unmarked directory blocks selected skill $skill on $destination: $target"
            printf '%s\t%s\tunmarked-directory\n' "$skill" "$destination" >> "$SKIPPED_TSV"
          fi
          ;;
        3)
          append_error "foreign-owned directory blocks selected skill $skill on $destination: $target"
          printf '%s\t%s\tother-owner\n' "$skill" "$destination" >> "$SKIPPED_TSV"
          ;;
        *)
          reason=missing
          [ -e "$target" ] || [ -L "$target" ] || reason=missing
          [ ! -e "$target" ] && [ ! -L "$target" ] || reason=changed
          printf '%s\t%s\t%s\t%s\tinstall\n' "$source_id" "$skill" "$destination" "$reason" >> "$DRIFT_TSV"
          ;;
      esac
    fi
  done < "$desired"

  [ -d "$root" ] || return 0
  shopt -s nullglob
  for marker in "$root"/*/.agent-scripts-copy; do
    [ -f "$marker" ] || continue
    marker_owner="$(sed -n '2p' "$marker" 2>/dev/null || true)"
    is_managed_owner "$marker_owner" || continue
    name="$(basename "$(dirname "$marker")")"
    if ! rg -Fxq -- "$name" "$selected"; then
      printf 'matrix\t%s\t%s\tunselected\tremove\n' "$name" "$destination" >> "$DRIFT_TSV"
    fi
  done
  for target in "$root"/*; do
    [ -d "$target" ] || [ -L "$target" ] || continue
    name="$(basename "$target")"
    marker_owner="$(sed -n '2p' "$target/.agent-scripts-copy" 2>/dev/null || true)"
    is_managed_owner "$marker_owner" && continue
    skipped_reason=unmarked-directory
    [ -n "$marker_owner" ] && skipped_reason=other-owner
    # A directory with planned drift is one this run is about to take over, so
    # it is not being preserved and must not be reported as such.
    if ! is_skipped "$name" "$destination" && ! has_drift "$name" "$destination"; then
      printf '%s\t%s\t%s\n' "$name" "$destination" "$skipped_reason" >> "$SKIPPED_TSV"
      append_warning "preserving $skipped_reason on $destination: $name"
    fi
  done
  shopt -u nullglob
}

if [ "$roots_safe" -eq 1 ]; then
  inspect_surface claude "$CLAUDE_ROOT" "$CLAUDE_DESIRED" "$CLAUDE_SELECTED"
  inspect_surface codex "$CODEX_ROOT" "$CODEX_DESIRED" "$CODEX_SELECTED"
fi

apply_surface() { # destination root desired_tsv
  local destination="$1" root="$2" desired="$3"
  local skill source_id source_path action reason
  mkdir -p "$root" || { append_error "could not create skill surface: $root"; return; }
  while IFS=$'\t' read -r skill source_id source_path; do
    [ -n "$skill" ] || continue
    if is_skipped "$skill" "$destination"; then
      continue
    fi
    if has_drift "$skill" "$destination"; then
      if install_skill_copy "$source_path" "$root/$skill" "$OWNER" "$source_path"; then
        printf '%s\t%s\t%s\tinstalled\n' "$source_id" "$skill" "$destination" >> "$CHANGES_TSV"
      else
        append_error "failed to install $skill on $destination"
      fi
    fi
  done < "$desired"
  while IFS=$'\t' read -r source_id skill drift_destination reason action; do
    [ "$drift_destination" = "$destination" ] || continue
    [ "$action" = remove ] || continue
    if rm -rf -- "$root/$skill"; then
      printf '%s\t%s\t%s\tremoved\n' "$source_id" "$skill" "$destination" >> "$CHANGES_TSV"
    else
      append_error "failed to remove unselected managed copy $skill on $destination"
    fi
  done < "$DRIFT_TSV"
}

if [ "$MODE" = reconcile ] && [ "$roots_safe" -eq 1 ]; then
  apply_surface claude "$CLAUDE_ROOT" "$CLAUDE_DESIRED"
  apply_surface codex "$CODEX_ROOT" "$CODEX_DESIRED"
fi

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
