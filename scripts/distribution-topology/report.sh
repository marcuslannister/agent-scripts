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

topology_write_human() { # document
  local document="$1" source_id inventory defaults supported result
  printf 'Skill topology %s\n' "$(jq -r '.mode' "$document")"
  printf '%-20s%-11s%-14s%-14s%s\n' SOURCE INVENTORY DEFAULT SUPPORTED RESULT
  while IFS=$'\t' read -r source_id inventory defaults supported result; do
    printf '%-20s%-11s%-14s%-14s%s\n' "$source_id" "$inventory" "$defaults" "$supported" "$result"
  done < <(jq -r '.sources[] | [.id, .inventoryCount, (.defaultDestinations | join(",")), (.supportedDestinations | join(",")), .result] | @tsv' "$document")

  if [ "$(jq '.drift | length' "$document")" -gt 0 ]; then printf '\nDrift:\n'; fi
  jq -r '.drift[] | "- \(.sourceId)/\(.skill) -> \(.destination): \(.reason)"' "$document"
  if [ "$(jq '.changes | length' "$document")" -gt 0 ]; then printf '\nChanges:\n'; fi
  jq -r '.changes[] | "- \(.action) \(.sourceId)/\(.skill) -> \(.destination)"' "$document"

  printf '\nCodex-root hygiene: %s\n' "$(jq -r '.hygiene.status' "$document")"
  jq -r '.hygiene.entries[] | "- legacy entry \(.name): \(.kind)"' "$document"
  jq -r '.hygiene.changes[] | "- migrated \(.name) -> \(.backupPath)"' "$document"
  if [ "$(jq '.skipped | length' "$document")" -gt 0 ]; then printf '\nSkipped:\n'; fi
  jq -r '.skipped[] | "- \(.sourceId)/\(.skill) -> \(.destination): \(.reason)"' "$document"

  local count count_label status mode
  mode="$(jq -r '.mode' "$document")"
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
  printf '\nResult: %s (%s)\n' "$status" "$count_label"

  if [ "$(jq '.decisions | length' "$document")" -gt 0 ]; then
    printf 'Decision required:\n' >&2
    jq -r '.decisions[] | "- \(.message)"' "$document" >&2
  fi
  jq -r '.warnings[] | "warning: \(.message)"' "$document" >&2
  jq -r '.errors[] | "error: \(.)"' "$document" >&2
}
