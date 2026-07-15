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
    "$fixture/codex-skills/maintainer-orchestrator/agents"
  cp "$REPO_ROOT/scripts/test-maintainer-orchestrator-policy" "$fixture/scripts/"
  cp "$REPO_ROOT/codex-skills/maintainer-orchestrator/SKILL.md" \
    "$fixture/codex-skills/maintainer-orchestrator/SKILL.md"
  cp "$REPO_ROOT/codex-skills/maintainer-orchestrator/agents/openai.yaml" \
    "$fixture/codex-skills/maintainer-orchestrator/agents/openai.yaml"

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
grep -F "Validated maintainer-orchestrator worker boundary." "$valid_fixture/out" >/dev/null

requirement_labels=(
  "Codex app workers only"
  "one project thread per repository"
  "root-owned skill maintenance"
  "no project task fan-out"
  "pre-spawn classification"
  "mutating work routing"
  "support-only subagents"
  "subagent mutation ban"
  "preservation-first recovery"
  "thread-owned execution"
  "text is not capability"
  "permission propagation check"
  "no repeated permission prompts"
  "single heartbeat inspection"
  "private concurrency invariant"
  "single public admission gate"
  "frozen means public only"
  "decision wait does not idle"
)
requirement_texts=(
  "a worker is an owned Codex app thread, never a collaboration subagent"
  "Use exactly one owned Codex app project thread per repository"
  'Maintain this canonical `maintainer-orchestrator` skill in the current root orchestrator session, never in a project thread or collaboration subagent.'
  "project threads never create task threads"
  "Before spawning a collaboration subagent, classify the task"
  "Any repository task that can mutate repository, GitHub, or external state"
  "Use collaboration subagents only for orchestration support"
  "Collaboration subagents must never edit repository files, create commits, run implementation proof as the owner, push, mutate PRs/issues, approve workflows, merge, release, deploy, or perform live product/account proof."
  "Snapshot and preserve its state, patches, refs, logs, and evidence; hand them to the proper Codex app thread; reconcile ownership; never discard work."
  "Project execution remains owned and performed by its Codex app thread"
  "Thread prompts do not grant capabilities"
  "verify its effective permission profile"
  "Do not retry the same denied action or repeatedly prompt the owner."
  "inspect the existing heartbeat first"
  "Private investigation, implementation, testing, proof, and review continue independently."
  "admit no additional public action until the overlap clears"
  "means public-mutation-frozen only when that restriction existed before the worker crossed the public boundary"
  "Keep all other qualified private project lanes active while that answer is pending."
)

for index in "${!requirement_labels[@]}"; do
  fixture="$(create_fixture "missing-$index")"
  replace_text \
    "$fixture/codex-skills/maintainer-orchestrator/SKILL.md" \
    "${requirement_texts[$index]}" \
    ""
  assert_failure \
    "$fixture" \
    "Missing maintainer-orchestrator policy: ${requirement_labels[$index]}"
done

for term in subthread Subthreads; do
  fixture="$(create_fixture "ambiguous-$term")"
  printf '\n%s\n' "$term" >>"$fixture/codex-skills/maintainer-orchestrator/SKILL.md"
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
    >>"$fixture/codex-skills/maintainer-orchestrator/SKILL.md"
  assert_failure "$fixture" "Task-thread fan-out remains"
done

metadata_requirements=(
  "one Codex app thread per project"
  "skill maintenance in the root session"
  "collaboration subagents read-only and support-only"
)
for index in "${!metadata_requirements[@]}"; do
  fixture="$(create_fixture "metadata-$index")"
  replace_text \
    "$fixture/codex-skills/maintainer-orchestrator/agents/openai.yaml" \
    "${metadata_requirements[$index]}" \
    ""
  assert_failure "$fixture" "Stale maintainer-orchestrator default prompt"
done

missing_skill_fixture="$(create_fixture missing-skill)"
rm "$missing_skill_fixture/codex-skills/maintainer-orchestrator/SKILL.md"
assert_failure "$missing_skill_fixture" "Missing maintainer-orchestrator skill:"

missing_metadata_fixture="$(create_fixture missing-metadata)"
rm "$missing_metadata_fixture/codex-skills/maintainer-orchestrator/agents/openai.yaml"
assert_failure "$missing_metadata_fixture" "Missing maintainer-orchestrator metadata:"

echo "maintainer-orchestrator policy tests passed"
