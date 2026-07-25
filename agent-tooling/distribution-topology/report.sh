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
  jq -n --arg message "$1" --argjson code "$2" --arg mode "$3" \
    --arg claudeRootPath "${CLAUDE_ROOT_PATH:-}" --arg claudeRootState "${CLAUDE_ROOT_STATE:-unknown}" \
    --arg claudeRootAction "${CLAUDE_ROOT_ACTION:-none}" --arg claudeRootMessage "${CLAUDE_ROOT_MESSAGE:-}" '
    (if $code == 2 then "invalid" elif $code == 130 then "interrupted" else "failed" end) as $status |
    {
      schemaVersion: 1, mode: $mode, status: $status,
      policy: {scope:"dual-plugin-migrations",distribution:"plugin-managed",fallback:"forbidden"},
      recovery: {required:false,actions:[]},
      state: "failed", idempotent: false,
      events: [{kind:"blocking-failure",status:"failed",message:$message}],
      sources: [], plan: [], drift: [], decisions: [], errors: [$message],
      warnings: [], changes: [], skipped: [], migrations: [],
      claudeRoot: {path:$claudeRootPath,state:$claudeRootState,action:$claudeRootAction,message:$claudeRootMessage},
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

topology_result_color() { # result
  case "$1" in
    clean|reconciled|changed|verified|applied|removed) printf '%s' "$TOPOLOGY_GREEN" ;;
    drift|decision-required|skipped|planned|blocked|retained) printf '%s' "$TOPOLOGY_YELLOW" ;;
    failed|invalid|interrupted) printf '%s' "$TOPOLOGY_RED" ;;
  esac
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
    result_color="$(topology_result_color "$result")"
    printf '%-32s %-18s %-30s %s%s%s\n' \
      "$source" "$destination" "$change" "$result_color" "$result" "$TOPOLOGY_RESET"
  done < <(jq -r '
    . as $document |
    def source_result($id):
      ([$document.sources[] | select(.id == $id) | .result][0] // $document.status);
    ([
      $document.changes[] as $change |
      select(any($document.events[];
        (.kind == "native-reconciliation" or .kind == "copy-removal") and
        .sourceId == $change.sourceId and
        .skill == $change.skill and
        .destination == $change.destination
      ) | not) |
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
       change:(if $document.mode == "check" and $drift.reason == "unexpected"
         then "planned-removal" else $drift.reason end),
       result:source_result($drift.sourceId)}
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
      $document.events[] |
      {
        source:((.sourceId // "topology") +
          (if .skill? then "/" + .skill else "" end)),
        destination:(.destination // "-"),
        change:(
          if .kind == "native-reconciliation" then
            "native-" + .phase + ":" + .action
          elif .kind == "runtime-verification" then
            "runtime-verification" + (if .reason? then ":" + .reason else "" end)
          elif .kind == "copy-retained" then
            "copy-retained:" + .reason
          elif .kind == "copy-removal" then
            "copy-removal"
          else "blocking-failure" end
        ),
        result:.status
      }
    ] + [
      $document.hygiene.changes[] |
      {source:("codex-root/" + .name), destination:$document.hygiene.legacyRoot,
       change:"migrated", result:$document.hygiene.status}
    ] + [
      $document.hygiene.entries[] |
      {source:("codex-root/" + .name), destination:$document.hygiene.legacyRoot,
       change:("legacy:" + .kind), result:$document.hygiene.status}
    ]) as $report_rows |
    ($report_rows + [
      $document.sources[] as $source |
      select(any($report_rows[];
        .source == $source.id or (.source | startswith($source.id + "/"))) | not) |
      {source:$source.id,
       destination:(([$document.plan[] | select(.sourceId == $source.id) | .destinations[]] | unique | join(","))
         // ($source.defaultDestinations | join(","))),
       change:"none", result:$source.result}
    ]) as $all_rows |
    (if ($all_rows | length) == 0
      or (($document.status == "failed" or $document.status == "invalid" or $document.status == "interrupted")
        and (any($all_rows[];
          .change == $document.status and .result == $document.status) | not)) then
      $all_rows + [{source:"topology",destination:"-",change:$document.status,result:$document.status}]
    else $all_rows end) |
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
  result_color="$(topology_result_color "$status")"
  printf '\nResult: %s%s%s (%s)\n' "$result_color" "$status" "$TOPOLOGY_RESET" "$count_label"

  if [ "$(jq '.decisions | length' "$document")" -gt 0 ]; then
    printf 'Decision required:\n' >&2
    jq -r '.decisions[] | "- \(.message)"' "$document" >&2
  fi
  jq -r '.warnings[] | "warning: \(.message)"' "$document" >&2
  jq -r '.errors[] | "error: \(.)"' "$document" >&2
  if jq -e '.recovery.required == true' "$document" >/dev/null; then
    printf 'Recovery: upstream repair, native rollback, or explicit manifest decision.
' >&2
  fi
}

topology_write_human_failure() { # message code mode
  local failure_document
  failure_document="$(mktemp "${TMPDIR:-/tmp}/agent-scripts-topology-failure.XXXXXX")"
  topology_failure_document "$1" "$2" "$3" > "$failure_document"
  topology_write_human "$failure_document"
  rm -f -- "$failure_document"
}

topology_write_failure() { # message code mode
  if [ "$REQUESTED_JSON" -eq 1 ]; then
    topology_failure_document "$1" "$2" "$3"
  else
    topology_write_human_failure "$1" "$2" "$3"
  fi
}
