#!/usr/bin/env bash
set -euo pipefail

target_repo="openclaw/openclaw"
clawsweeper_repo="openclaw/clawsweeper"
hours="6"
limit="8"
run_limit="100"
bot_regex='(clawsweeper|openclaw-ci|github-actions)'

usage() {
  cat <<'USAGE'
Usage: clawsweeper-status.sh [--repo owner/name] [--hours N] [--limit N]

Shows recent ClawSweeper activity and worker health:
  - recently merged PRs
  - recently reviewed/commented items
  - recently closed items
  - active workflows and estimated active Codex jobs
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      target_repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --clawsweeper-repo)
      clawsweeper_repo="${2:?missing value for --clawsweeper-repo}"
      shift 2
      ;;
    --hours)
      hours="${2:?missing value for --hours}"
      shift 2
      ;;
    --limit)
      limit="${2:?missing value for --limit}"
      shift 2
      ;;
    --run-limit)
      run_limit="${2:?missing value for --run-limit}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

since="$(date -u -v-"${hours}"H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "${hours} hours ago" '+%Y-%m-%dT%H:%M:%SZ')"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runs_json="$tmpdir/runs.json"
all_runs_jsonl="$tmpdir/all-runs.jsonl"
comments_json="$tmpdir/comments.json"
closed_items_json="$tmpdir/closed-items.json"
pulls_json="$tmpdir/pulls.json"
jobs_jsonl="$tmpdir/jobs.jsonl"

activity_page_size=$((limit * 3))
if [ "$activity_page_size" -lt 10 ]; then
  activity_page_size=10
elif [ "$activity_page_size" -gt 20 ]; then
  activity_page_size=20
fi

normalize_runs='.[] | {
  id: .databaseId,
  name,
  status,
  conclusion,
  created_at: .createdAt,
  html_url: .url
}'

fetch_activity_page() {
  local endpoint_template="$1"
  local output="$2"
  local page_size="$activity_page_size"
  local error_file="$tmpdir/activity-error"

  while :; do
    if gh api "${endpoint_template/__PAGE__/$page_size}" >"$output" 2>"$error_file"; then
      return 0
    fi
    if [ "$page_size" -eq 1 ]; then
      cat "$error_file" >&2
      return 1
    fi
    page_size=$((page_size / 2))
    [ "$page_size" -lt 1 ] && page_size=1
  done
}

: >"$all_runs_jsonl"
gh run list --repo "$clawsweeper_repo" --limit "$run_limit" \
  --json databaseId,name,status,conclusion,createdAt,url \
  | jq -c "$normalize_runs" >>"$all_runs_jsonl"
run_query_failures=0
run_query_truncated=0
for status in in_progress queued waiting pending requested; do
  status_runs_json="$tmpdir/runs-${status}.json"
  if gh run list --repo "$clawsweeper_repo" --status "$status" --limit "$run_limit" \
    --json databaseId,name,status,conclusion,createdAt,url >"$status_runs_json"; then
    jq -c "$normalize_runs" "$status_runs_json" >>"$all_runs_jsonl"
    status_run_count="$(jq 'length' "$status_runs_json")"
    if [ "$status_run_count" -ge "$run_limit" ]; then
      run_query_truncated=$((run_query_truncated + 1))
    fi
  else
    run_query_failures=$((run_query_failures + 1))
  fi
done
jq -s '
  {
    workflow_runs: (
      unique_by(.id)
      | sort_by(.created_at)
      | reverse
    )
  }
' "$all_runs_jsonl" >"$runs_json"
fetch_activity_page "repos/${target_repo}/issues/comments?sort=updated&direction=desc&per_page=__PAGE__&since=${since}" "$comments_json"
closed_search="repo:${target_repo} is:closed closed:>=${since} sort:updated-desc"
# GraphQL variable references must remain literal for gh to bind them.
# shellcheck disable=SC2016
closed_query='query($searchQuery: String!, $first: Int!) {
  search(type: ISSUE, query: $searchQuery, first: $first) {
    nodes {
      ... on Issue {
        title url closedAt
        timelineItems(last: 1, itemTypes: [CLOSED_EVENT]) {
          nodes { ... on ClosedEvent { createdAt actor { login } } }
        }
      }
      ... on PullRequest {
        title url closedAt
        timelineItems(last: 1, itemTypes: [CLOSED_EVENT]) {
          nodes { ... on ClosedEvent { createdAt actor { login } } }
        }
      }
    }
  }
}'
gh api graphql -f query="$closed_query" -f searchQuery="$closed_search" \
  -F first="$activity_page_size" >"$closed_items_json"
gh pr list --repo "$target_repo" --state merged \
  --search "merged:>=${since} sort:updated-desc" --limit "$activity_page_size" \
  --json title,url,mergedAt,mergedBy,labels >"$pulls_json"

in_progress_count="$(jq '[.workflow_runs[] | select(.status == "in_progress")] | length' "$runs_json")"
job_probe_limit=40
active_ids="$(jq -r --argjson limit "$job_probe_limit" '[.workflow_runs[]
  | select(.status == "in_progress")
  | .id][0:$limit][]' "$runs_json")"
if [ "$in_progress_count" -gt "$job_probe_limit" ]; then
  unprobed_job_runs=$((in_progress_count - job_probe_limit))
else
  unprobed_job_runs=0
fi

: >"$jobs_jsonl"
job_batch_size=8
job_batch_count=0
while IFS= read -r run_id; do
  [ -n "$run_id" ] || continue
  (
    if jobs="$(gh run view "$run_id" --repo "$clawsweeper_repo" --json jobs \
      --jq '[.jobs[] | {name,status,conclusion}]' 2>/dev/null)"; then
      jq -cn --argjson jobs "$jobs" '{jobs: $jobs, query_failed: false}'
    else
      jq -cn '{jobs: [], query_failed: true}'
    fi
  ) >"$tmpdir/jobs-${run_id}.json" &
  job_batch_count=$((job_batch_count + 1))
  if [ "$job_batch_count" -ge "$job_batch_size" ]; then
    wait
    job_batch_count=0
  fi
done <<<"$active_ids"
wait
for job_file in "$tmpdir"/jobs-*.json; do
  [ -e "$job_file" ] || continue
  cat "$job_file" >>"$jobs_jsonl"
done

active_count="$(jq '[.workflow_runs[] | select(.status == "in_progress" or .status == "pending" or .status == "queued" or .status == "waiting")] | length' "$runs_json")"
queued_count="$(jq '[.workflow_runs[] | select(.status == "queued" or .status == "waiting")] | length' "$runs_json")"
bad_count="$(jq '[.workflow_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "action_required")] | length' "$runs_json")"

codex_running="$(jq -s '[.[].jobs[]?
  | select(.status == "in_progress")
  | select(.name | test("Review shard|Review, comment|Review commit|Plan and review|Run worker|Execute credited fix|Codex"; "i"))
] | length' "$jobs_jsonl")"
codex_queued="$(jq -s '[.[].jobs[]?
  | select(.status == "queued" or .status == "waiting" or .status == "pending")
  | select(.name | test("Review shard|Review, comment|Review commit|Plan and review|Run worker|Execute credited fix|Codex"; "i"))
] | length' "$jobs_jsonl")"
job_query_failures="$(jq -s '[.[] | select(.query_failed)] | length' "$jobs_jsonl")"
job_query_failures=$((job_query_failures + unprobed_job_runs))
queued_codex_workflows="$(jq '[.workflow_runs[]
  | select(.status == "queued" or .status == "waiting" or .status == "pending")
  | select(.name | test("Review|repair|Run worker|Execute credited fix|Codex"; "i"))
] | length' "$runs_json")"
codex_queued=$((codex_queued + queued_codex_workflows))

echo "# ClawSweeper status"
echo
echo "Target: ${target_repo}"
echo "Window: last ${hours}h since ${since}"
echo
echo "## Workers"
echo
if [ "$run_query_failures" -gt 0 ] || [ "$run_query_truncated" -gt 0 ]; then
  printf -- "- Active workflow runs: at least %s (%s failed, %s truncated status queries)\n" "$active_count" "$run_query_failures" "$run_query_truncated"
else
  printf -- "- Active workflow runs: %s\n" "$active_count"
fi
if [ "$run_query_failures" -gt 0 ] || [ "$run_query_truncated" -gt 0 ]; then
  printf -- "- Queued/waiting workflow runs: at least %s\n" "$queued_count"
else
  printf -- "- Queued/waiting workflow runs: %s\n" "$queued_count"
fi
printf -- "- Failed/timed-out/action-required recent runs: %s\n" "$bad_count"
if [ "$job_query_failures" -gt 0 ] && { [ "$run_query_failures" -gt 0 ] || [ "$run_query_truncated" -gt 0 ]; }; then
  printf -- "- Estimated active Codex jobs: at least %s running, %s queued/pending (%s job queries unavailable; workflow status may be incomplete)\n" "$codex_running" "$codex_queued" "$job_query_failures"
elif [ "$job_query_failures" -gt 0 ]; then
  printf -- "- Estimated active Codex jobs: at least %s running, %s queued/pending (%s job queries unavailable)\n" "$codex_running" "$codex_queued" "$job_query_failures"
elif [ "$run_query_failures" -gt 0 ] || [ "$run_query_truncated" -gt 0 ]; then
  printf -- "- Estimated active Codex jobs: at least %s running, %s queued/pending (workflow status pages incomplete)\n" "$codex_running" "$codex_queued"
else
  printf -- "- Estimated active Codex jobs: %s running, %s queued/pending\n" "$codex_running" "$codex_queued"
fi
echo
jq -r '[.workflow_runs[]
  | select(.status == "in_progress" or .status == "pending" or .status == "queued" or .status == "waiting")
] | group_by(.name) | sort_by(-length) | .[]
  | "- \((length))x \((.[0].name)): \((.[0].html_url))"' "$runs_json" | head -20

print_section() {
  local title="$1"
  local body="$2"
  echo
  echo "## ${title}"
  echo
  if [ -n "$body" ]; then
    printf '%s\n' "$body"
  else
    echo "- none found in window"
  fi
}

merged="$(
  jq -r --arg since "$since" --argjson limit "$limit" '
    def one_line: gsub("[\r\n\t]+"; " ") | gsub("  +"; " ") | .[0:160];
    [.[] | select(.mergedAt != null and .mergedAt >= $since)
    ] | sort_by(.mergedAt) | reverse | .[0:$limit][]
    | "- \(.url) — \(.title | one_line) (merged \(.mergedAt))"
  ' "$pulls_json"
)"
print_section "Recently merged" "$merged"

reviewed="$(
  jq -r --arg bot "$bot_regex" --argjson limit "$limit" '
    def visible_line:
      split("\n")
      | map(gsub("[\r\t]+"; " ") | gsub("  +"; " ") | select(length > 0))
      | map(select(test("^<!--") | not))
      | (.[0] // "");
    def one_line: visible_line | .[0:180];
    [.[] | select((.user.login // "") | test($bot; "i"))
      | select((((.body // "") | test("clawsweeper-command-status"; "i"))) | not)
      | select((.body // "") | test("Codex review:|clawsweeper-action:review|ClawSweeper review"; "i"))
    ][0:$limit][]
    | "- \(.html_url) — #\(.issue_url | split("/")[-1]) \((.body // "") | one_line)"
  ' "$comments_json"
)"
print_section "Recently reviewed" "$reviewed"

commented="$(
  jq -r --arg bot "$bot_regex" --argjson limit "$limit" '
    def visible_line:
      split("\n")
      | map(gsub("[\r\t]+"; " ") | gsub("  +"; " ") | select(length > 0))
      | map(select(test("^<!--") | not))
      | (.[0] // "");
    def one_line: visible_line | .[0:180];
    [.[] | select((.user.login // "") | test($bot; "i"))
      | select((((.body // "") | test("Codex review:|clawsweeper-action:review|ClawSweeper review"; "i"))) | not)
    ][0:$limit][]
    | "- \(.html_url) — #\(.issue_url | split("/")[-1]) \((.body // "") | one_line)"
  ' "$comments_json"
)"
print_section "Recently commented" "$commented"

closed="$(
  jq -r --arg bot "$bot_regex" --arg since "$since" --argjson limit "$limit" '
    def one_line: gsub("[\r\n\t]+"; " ") | gsub("  +"; " ") | .[0:160];
    [.data.search.nodes[]
      | .timelineItems.nodes[0] as $event
      | select(.closedAt >= $since)
      | select(($event.actor.login // "") | test($bot; "i"))
      | {title, url, closed_at: .closedAt, actor: $event.actor.login}
    ] | sort_by(.closed_at) | reverse | .[0:$limit][]
    | "- \(.url) — \(.title | one_line) (closed by \(.actor) at \(.closed_at))"
  ' "$closed_items_json"
)"
print_section "Recently closed" "$closed"
