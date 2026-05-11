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
recent_runs_json="$tmpdir/recent-runs.json"
active_runs_jsonl="$tmpdir/active-runs.jsonl"
comments_json="$tmpdir/comments.json"
events_json="$tmpdir/events.json"
closed_items_json="$tmpdir/closed-items.json"
closed_items_jsonl="$tmpdir/closed-items.jsonl"
pulls_json="$tmpdir/pulls.json"
jobs_jsonl="$tmpdir/jobs.jsonl"

gh api "repos/${clawsweeper_repo}/actions/runs?per_page=${run_limit}" >"$recent_runs_json"
: >"$active_runs_jsonl"
for status in in_progress queued waiting pending requested; do
  gh api "repos/${clawsweeper_repo}/actions/runs?status=${status}&per_page=${run_limit}" \
    | jq -c '.workflow_runs[]?' >>"$active_runs_jsonl" || true
done
jq -s '
  {
    workflow_runs: (
      (.[0].workflow_runs + (.[1:] | map(. // empty)))
      | unique_by(.id)
      | sort_by(.created_at)
      | reverse
    )
  }
' "$recent_runs_json" "$active_runs_jsonl" >"$runs_json"
gh api "repos/${target_repo}/issues/comments?sort=updated&direction=desc&per_page=100&since=${since}" >"$comments_json"
gh api "repos/${target_repo}/issues/events?per_page=100" >"$events_json"
gh api "repos/${target_repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100" >"$pulls_json"

: >"$closed_items_jsonl"
for page in $(seq 1 20); do
  page_json="$tmpdir/closed-items-page-${page}.json"
  gh api -X GET "repos/${target_repo}/issues" \
    -f state=closed \
    -f since="$since" \
    -f sort=updated \
    -f direction=desc \
    -f per_page=100 \
    -f page="$page" >"$page_json" || break
  page_count="$(jq 'length' "$page_json")"
  jq -c --arg since "$since" '
    .[]
    | select(.closed_at != null and .closed_at >= $since)
  ' "$page_json" >>"$closed_items_jsonl"
  [ "$page_count" -lt 100 ] && break
done
jq -s '.' "$closed_items_jsonl" >"$closed_items_json"

active_ids="$(jq -r '.workflow_runs[]
  | select(.status == "in_progress" or .status == "pending" or .status == "queued" or .status == "waiting")
  | .id' "$runs_json")"

: >"$jobs_jsonl"
while IFS= read -r run_id; do
  [ -n "$run_id" ] || continue
  gh api "repos/${clawsweeper_repo}/actions/runs/${run_id}/jobs?per_page=100" >>"$jobs_jsonl" || true
  printf '\n' >>"$jobs_jsonl"
done <<<"$active_ids"

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

echo "# ClawSweeper status"
echo
echo "Target: ${target_repo}"
echo "Window: last ${hours}h since ${since}"
echo
echo "## Workers"
echo
printf -- "- Active workflow runs: %s\n" "$active_count"
printf -- "- Queued/waiting workflow runs: %s\n" "$queued_count"
printf -- "- Failed/timed-out/action-required recent runs: %s\n" "$bad_count"
printf -- "- Estimated active Codex jobs: %s running, %s queued/pending\n" "$codex_running" "$codex_queued"
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
    [.[] | select(.merged_at != null and .merged_at >= $since)
      | select(((.labels // []) | map(.name) | join(" ") | test("clawsweeper"; "i")) or ((.merged_by.login // "") | test("clawsweeper|openclaw-ci|github-actions"; "i")))
    ][0:$limit][]
    | "- \(.html_url) — \(.title | one_line) (merged \(.merged_at))"
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
      | select((.body | test("clawsweeper-command-status"; "i")) | not)
      | select(.body | test("Codex review:|clawsweeper-action:review|ClawSweeper review"; "i"))
    ][0:$limit][]
    | "- \(.html_url) — #\(.issue_url | split("/")[-1]) \(.body | one_line)"
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
      | select((.body | test("Codex review:|clawsweeper-action:review|ClawSweeper review"; "i")) | not)
    ][0:$limit][]
    | "- \(.html_url) — #\(.issue_url | split("/")[-1]) \(.body | one_line)"
  ' "$comments_json"
)"
print_section "Recently commented" "$commented"

closed="$(
  jq -r --arg bot "$bot_regex" --argjson limit "$limit" '
    def one_line: gsub("[\r\n\t]+"; " ") | gsub("  +"; " ") | .[0:160];
    [.[] | select((.closed_by.login // "") | test($bot; "i"))
    ] | sort_by(.closed_at) | reverse | .[0:$limit][]
    | "- \(.html_url) — \(.title | one_line) (closed by \(.closed_by.login) at \(.closed_at))"
  ' "$closed_items_json"
)"
print_section "Recently closed" "$closed"
