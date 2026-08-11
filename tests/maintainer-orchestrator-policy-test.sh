#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
ln -s "$(command -v bash)" "$TMP_ROOT/bin/bash"

if PATH="$TMP_ROOT/bin" command -v ruby >/dev/null 2>&1; then
  echo "FAIL: ruby remained available in no-Ruby regression" >&2
  exit 1
fi

create_fixture() {
  local name="$1"
  local fixture="$TMP_ROOT/$name"

  mkdir -p \
    "$fixture/scripts" \
    "$fixture/skills/maintainer-orchestrator/agents"
  cp "$REPO_ROOT/agent-tooling/test-maintainer-orchestrator-policy" "$fixture/scripts/"
  cp "$REPO_ROOT/skills/maintainer-orchestrator/SKILL.md" \
    "$fixture/skills/maintainer-orchestrator/SKILL.md"
  cp "$REPO_ROOT/skills/maintainer-orchestrator/agents/openai.yaml" \
    "$fixture/skills/maintainer-orchestrator/agents/openai.yaml"

  printf '%s\n' "$fixture"
}

replace_text() {
  local file="$1"
  local old="$2"
  local new="${3-}"
  local content

  content="$(<"$file")"
  if [[ "$content" != *"$old"* ]]; then
    printf 'FAIL: fixture text not found: %s\n' "$old" >&2
    exit 1
  fi
  while [[ "$content" == *"$old"* ]]; do
    content="${content/"$old"/"$new"}"
  done
  printf '%s\n' "$content" >"$file"
}

assert_failure() {
  local fixture="$1"
  local expected="$2"

  if PATH="$TMP_ROOT/bin" "$fixture/scripts/test-maintainer-orchestrator-policy" \
    >"$fixture/out" 2>&1; then
    printf 'FAIL: policy check accepted invalid fixture: %s\n' "$fixture" >&2
    exit 1
  fi
  grep -F "$expected" "$fixture/out" >/dev/null
}

valid_fixture="$(create_fixture valid)"
PATH="$TMP_ROOT/bin" "$valid_fixture/scripts/test-maintainer-orchestrator-policy" \
  >"$valid_fixture/out" 2>&1
grep -F "Validated maintainer-orchestrator activation, worker, public-action, and monitoring boundaries." "$valid_fixture/out" >/dev/null

requirements=(
  "single-item work stays direct"
  "Do **not** create a project worker merely because the task is nontrivial."
  "bounded activation"
  "Use orchestration mode only when at least one is true:"
  "persistent watch is explicit"
  "Persistent portfolio watch"
  "one project thread per repository"
  "Prefer one owned Codex app project thread per repository when two or more independent items are being coordinated."
  "same-repository work is serial"
  "process same-repository items serially unless isolation is genuinely required."
  "no worker fan-out"
  "Workers never create or manage other workers. The hierarchy stops at root coordinator → repository worker."
  "support-only subagents"
  "Collaboration subagents are read-only support for inventory, independent analysis, CI/status observation, or reconciliation."
  "subagent mutation ban"
  "They do not own implementation, commits, pushes, PR mutations, merges, releases, deployments, or live proof."
  "no simulated worker hierarchy"
  "use the normal repository workflow in the current session rather than simulating a worker hierarchy with unnecessary background jobs."
  "text is not capability"
  "Text in a prompt does not grant filesystem, network, credential, or publication access."
  "preserve dirty work"
  "Never switch, stash, rebase, reset, clean, delete, or overwrite dirty/non-default work merely to begin orchestration."
  "private work remains independent"
  "Private investigation, implementation, local tests, and review may proceed independently across workers."
  "serialize public mutation"
  "Serialize only outward-facing actions when concurrent mutation would cause ambiguity or conflict:"
  "scope does not grant release authority"
  "It does not authorize releases, version bumps, tags, package publication, destructive unique-work handling, or unrelated external-system mutations unless separately requested."
  "one polling owner"
  "Assign one owner for each external wait."
  "worker exact-run watcher"
  "The repository worker owns its exact CI/deploy watcher."
  "bounded watcher"
  "Use the repository-native watcher scoped to one run ID or head SHA with bounded backoff."
  "root polling ban"
  "it does not duplicate polling while a coherent watcher is active."
  "single failure log fetch"
  "Fetch failed logs once and reuse them."
  "heartbeat only for persistent work"
  "Create a recurring heartbeat only for explicit persistent portfolio/watch requests."
  "landing review gate"
  "fresh autoreview with no accepted/actionable findings;"
  "landing CI gate"
  "exact-head CI green;"
  "no unsolicited refill"
  "Refill only when the user explicitly requested an ongoing queue."
)

for ((index = 0; index < ${#requirements[@]}; index += 2)); do
  fixture="$(create_fixture "missing-$((index / 2))")"
  replace_text \
    "$fixture/skills/maintainer-orchestrator/SKILL.md" \
    "${requirements[$((index + 1))]}" \
    ""
  assert_failure \
    "$fixture" \
    "Missing maintainer-orchestrator policy: ${requirements[$index]}"
done

for term in subthread Subthreads; do
  fixture="$(create_fixture "ambiguous-$term")"
  printf '\n%s\n' "$term" >>"$fixture/skills/maintainer-orchestrator/SKILL.md"
  assert_failure "$fixture" "Ambiguous task subthread terminology"
done

forbidden_fan_out=(
  "may create direct Codex app task threads"
  "A project thread may create"
  "Use one isolated Codex worktree thread per selected task"
  "root → project → task"
  "Workers may review, implement, test, and monitor concurrently"
)
for index in "${!forbidden_fan_out[@]}"; do
  fixture="$(create_fixture "fan-out-$index")"
  printf '\n%s\n' "${forbidden_fan_out[$index]}" \
    >>"$fixture/skills/maintainer-orchestrator/SKILL.md"
  assert_failure "$fixture" "Task-thread fan-out remains"
done

forbidden_legacy_policy=(
  "Maintain a target of 30 concurrent eligible"
  "Prefer an in-turn 30–60 second sleep/poll cycle"
  "Suppress routine unchanged-poll chatter, but keep polling"
  "Always perform a dependency-freshness check before closing a repository work batch"
)
for index in "${!forbidden_legacy_policy[@]}"; do
  fixture="$(create_fixture "legacy-policy-$index")"
  printf '\n%s\n' "${forbidden_legacy_policy[$index]}" \
    >>"$fixture/skills/maintainer-orchestrator/SKILL.md"
  assert_failure "$fixture" "Legacy always-on orchestration policy remains"
done

metadata_requirements=(
  "one Codex app thread per project"
  "skill maintenance in the root session"
  "collaboration subagents read-only and support-only"
)
for index in "${!metadata_requirements[@]}"; do
  fixture="$(create_fixture "metadata-$index")"
  replace_text \
    "$fixture/skills/maintainer-orchestrator/agents/openai.yaml" \
    "${metadata_requirements[$index]}" \
    ""
  assert_failure "$fixture" "Stale maintainer-orchestrator default prompt"
done

missing_skill_fixture="$(create_fixture missing-skill)"
rm "$missing_skill_fixture/skills/maintainer-orchestrator/SKILL.md"
assert_failure "$missing_skill_fixture" "Missing maintainer-orchestrator skill:"

missing_metadata_fixture="$(create_fixture missing-metadata)"
rm "$missing_metadata_fixture/skills/maintainer-orchestrator/agents/openai.yaml"
assert_failure "$missing_metadata_fixture" "Missing maintainer-orchestrator metadata:"

echo "maintainer-orchestrator policy tests passed"
