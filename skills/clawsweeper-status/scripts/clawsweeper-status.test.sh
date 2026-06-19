#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_TEST_LOG:?}"

case "$1 $2" in
  "run list")
    if [[ " $* " == *" --status in_progress "* ]]; then
      printf '%s\n' '[{"databaseId":21,"name":"ClawSweeper review","status":"in_progress","conclusion":null,"createdAt":"2099-01-01T00:00:00Z","url":"https://github.test/runs/21"}]'
    elif [[ " $* " == *" --status queued "* ]]; then
      printf '%s\n' '[{"databaseId":22,"name":"ClawSweeper review","status":"queued","conclusion":null,"createdAt":"2099-01-01T00:00:00Z","url":"https://github.test/runs/22"}]'
    elif [[ " $* " == *" --status "* ]]; then
      printf '%s\n' '[]'
    else
      printf '%s\n' '[{"databaseId":11,"name":"Sweep","status":"completed","conclusion":"failure","createdAt":"2099-01-01T00:00:00Z","url":"https://github.test/runs/11"}]'
    fi
    ;;
  "run view")
    printf '%s\n' '[{"name":"Review shard 1","status":"in_progress","conclusion":null}]'
    ;;
  "pr list")
    printf '%s\n' '[{"title":"Generated repair","url":"https://github.test/pull/7","mergedAt":"2099-01-01T00:00:00Z","mergedBy":{"login":"maintainer"},"labels":[]}]'
    ;;
  "api repos/test/target/issues/comments"*)
    if [[ "$*" == *"per_page=20"* ]]; then
      echo "github_response_too_large" >&2
      exit 1
    fi
    printf '%s\n' '[{"user":{"login":"clawsweeper"},"body":"Codex review: clean","html_url":"https://github.test/comment/8","issue_url":"https://api.github.test/issues/8"}]'
    ;;
  "api graphql")
    printf '%s\n' '{"data":{"search":{"nodes":[{"title":"Fixed issue","url":"https://github.test/issues/9","closedAt":"2099-01-01T00:00:00Z","timelineItems":{"nodes":[{"createdAt":"2099-01-01T00:00:00Z","actor":{"login":"clawsweeper"}}]}}]}}}'
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmpdir/gh"

export GH_TEST_LOG="$tmpdir/gh.log"
PATH="$tmpdir:$PATH" "$script_dir/clawsweeper-status.sh" \
  --repo test/target \
  --clawsweeper-repo test/sweeper \
  --limit 8 \
  --run-limit 12 >"$tmpdir/output"

grep -Fq -- '- Active workflow runs: 2' "$tmpdir/output"
grep -Fq -- '- Failed/timed-out/action-required recent runs: 1' "$tmpdir/output"
grep -Fq -- '- Estimated active Codex jobs: 1 running, 1 queued/pending' "$tmpdir/output"
grep -Fq 'https://github.test/pull/7' "$tmpdir/output"
grep -Fq 'https://github.test/comment/8' "$tmpdir/output"
grep -Fq 'https://github.test/issues/9' "$tmpdir/output"
grep -Fq 'run list --repo test/sweeper --limit 12 --json' "$GH_TEST_LOG"
grep -Fq 'issues/comments?sort=updated&direction=desc&per_page=20' "$GH_TEST_LOG"
grep -Fq 'issues/comments?sort=updated&direction=desc&per_page=10' "$GH_TEST_LOG"
if grep -Eq 'actions/runs|per_page=100|pulls\?state=closed' "$GH_TEST_LOG"; then
  echo "broad GitHub payload query detected" >&2
  exit 1
fi

echo "clawsweeper-status tests passed"
