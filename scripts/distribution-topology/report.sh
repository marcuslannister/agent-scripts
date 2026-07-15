#!/usr/bin/env bash

topology_help() {
  cat <<'EOF'
Usage: update-skill-topology.sh [--check] [--json]

Reconcile the manifest-owned skill distribution topology. Use --check to preview.

Options:
  --check  Discover inventory and report topology drift.
  --json   Write one JSON result document.
  -h, --help
            Show this help.

Exit codes:
  0   reconciled or check clean
  1   drift or verification failure
  2   invalid usage or manifest
  3   user decision required
  130 interrupted
EOF
}

topology_failure_document() { # message code mode
  jq -n --arg message "$1" --argjson code "$2" --arg mode "$3" '
    (if $code == 2 then "invalid" elif $code == 130 then "interrupted" else "failed" end) as $status |
    {
      schemaVersion: 1, mode: $mode, status: $status,
      sources: [], plan: [], drift: [], decisions: [], errors: [$message],
      warnings: [], changes: [], skipped: [],
      hygiene: {status: "failed", legacyRoot: "", entries: [], changes: [], errors: [$message]}
    }
  '
}

TOPOLOGY_BOLD=
TOPOLOGY_CYAN=
TOPOLOGY_GREEN=
TOPOLOGY_YELLOW=
TOPOLOGY_RED=
TOPOLOGY_RESET=

topology_init_color() {
  if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
    TOPOLOGY_BOLD=$'\033[1m'
    TOPOLOGY_CYAN=$'\033[36m'
    TOPOLOGY_GREEN=$'\033[32m'
    TOPOLOGY_YELLOW=$'\033[33m'
    TOPOLOGY_RED=$'\033[31m'
    TOPOLOGY_RESET=$'\033[0m'
  fi
}

topology_progress() { # step message
  [ "$JSON_OUTPUT" -eq 0 ] || return 0
  printf '%s[%s/4] %s%s\n' "$TOPOLOGY_CYAN" "$1" "$2" "$TOPOLOGY_RESET"
}

topology_write_human() { # document
  local document="$1" mode source destination change result result_color
  mode="$(jq -r '.mode' "$document")"
  printf 'Skill topology %s\n\n' "$mode"
  printf '%s%-32s %-18s %-30s %s%s\n' "$TOPOLOGY_BOLD" SOURCE DESTINATION CHANGE RESULT "$TOPOLOGY_RESET"
  while IFS=$'\t' read -r source destination change result; do
    result_color=
    case "$result" in
      clean|reconciled|changed) result_color="$TOPOLOGY_GREEN" ;;
      drift|decision-required|skipped) result_color="$TOPOLOGY_YELLOW" ;;
      failed|invalid|interrupted) result_color="$TOPOLOGY_RED" ;;
    esac
    printf '%-32s %-18s %-30s %s%s%s\n' \
      "$source" "$destination" "$change" "$result_color" "$result" "$TOPOLOGY_RESET"
  done < <(jq -r '
    . as $document |
    def source_result($id):
      ([$document.sources[] | select(.id == $id) | .result][0] // $document.status);
    ([
      $document.changes[] as $change |
      ([$document.drift[] | select(
        .sourceId == $change.sourceId and .skill == $change.skill and .destination == $change.destination
      ) | .reason][0] // "") as $reason |
      {source:($change.sourceId + "/" + $change.skill), destination:$change.destination,
       change:($change.action + (if $reason == "" then "" else ":" + $reason end)),
       result:source_result($change.sourceId)}
    ] + [
      $document.drift[] as $drift |
      select(any($document.changes[];
        .sourceId == $drift.sourceId and .skill == $drift.skill and .destination == $drift.destination) | not) |
      {source:($drift.sourceId + "/" + $drift.skill), destination:$drift.destination,
       change:$drift.reason, result:source_result($drift.sourceId)}
    ] + [
      $document.decisions[] |
      (.sourceId // ((.sourceIds // []) | join(",")) // "topology") as $sourceId |
      {source:($sourceId + (if .skill? then "/" + .skill else "" end)),
       destination:(.destination // "-"), change:(.code // "decision-required"),
       result:"decision-required"}
    ] + [
      $document.skipped[] |
      {source:(.sourceId + "/" + .skill), destination, change:("skipped:" + .reason), result:"skipped"}
    ] + [
      $document.hygiene.changes[] |
      {source:("codex-root/" + .name), destination:$document.hygiene.legacyRoot,
       change:"migrated", result:$document.hygiene.status}
    ] + [
      $document.hygiene.entries[] |
      {source:("codex-root/" + .name), destination:$document.hygiene.legacyRoot,
       change:("legacy:" + .kind), result:$document.hygiene.status}
    ]) as $activity |
    ($activity + [
      $document.sources[] as $source |
      select(any($activity[];
        .source == $source.id or (.source | startswith($source.id + "/"))) | not) |
      {source:$source.id,
       destination:(([$document.plan[] | select(.sourceId == $source.id) | .destinations[]] | unique | join(","))
         // ($source.defaultDestinations | join(","))),
       change:"none", result:$source.result}
    ]) |
    sort_by(.source,.destination,.change)[] |
    [.source, (if .destination == "" then "-" else .destination end), .change, .result] | @tsv
  ' "$document")

  local count count_label status
  status="$(jq -r '.status' "$document")"
  if [ "$(jq '.decisions | length' "$document")" -gt 0 ]; then
    count="$(jq '.decisions | length' "$document")"
    [ "$count" -eq 1 ] && count_label='1 decision' || count_label="$count decisions"
  else
    if [ "$mode" = check ]; then
      count="$(jq '[.drift,.hygiene.entries] | map(length) | add' "$document")"
    else
      count="$(jq '[.changes,.hygiene.changes] | map(length) | add' "$document")"
    fi
    count_label="$count changes"
  fi
  result_color=
  case "$status" in
    clean|reconciled) result_color="$TOPOLOGY_GREEN" ;;
    drift|decision-required) result_color="$TOPOLOGY_YELLOW" ;;
    failed|invalid|interrupted) result_color="$TOPOLOGY_RED" ;;
  esac
  printf '\nResult: %s%s%s (%s)\n' "$result_color" "$status" "$TOPOLOGY_RESET" "$count_label"

  if [ "$(jq '.decisions | length' "$document")" -gt 0 ]; then
    printf 'Decision required:\n' >&2
    jq -r '.decisions[] | "- \(.message)"' "$document" >&2
  fi
  jq -r '.warnings[] | "warning: \(.message)"' "$document" >&2
  jq -r '.errors[] | "error: \(.)"' "$document" >&2
}

topology_write_human_failure() { # message code mode
  local failure_document
  failure_document="$(mktemp "${TMPDIR:-/tmp}/agent-scripts-topology-failure.XXXXXX")"
  topology_failure_document "$1" "$2" "$3" > "$failure_document"
  topology_write_human "$failure_document"
  rm -f -- "$failure_document"
}
