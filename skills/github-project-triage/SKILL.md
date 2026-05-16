---
name: "github-project-triage"
description: "RepoBar GitHub queue triage: current project by default; steipete/openclaw issue and PR discovery when broad triage is requested."
---

# GitHub Project Triage

Use the current GitHub project by default when the user says "triage" from inside a repo. Use RepoBar as the first pass only for broad queue discovery across relevant owners/orgs. RepoBar is faster and more profile-aware than hand-rolling `gh repo list` loops, and it already understands repo activity, issue counts, PR counts, local projects, auth, cache, and filters.

## Setup

Prefer a real `repobar` binary when installed. In this workspace it may only exist as a SwiftPM product in `~/Projects/RepoBar`.

```bash
repobar_cmd() {
  if command -v repobar >/dev/null 2>&1; then
    repobar "$@"
  elif [ -x "$HOME/Projects/RepoBar/.build/debug/repobarcli" ]; then
    "$HOME/Projects/RepoBar/.build/debug/repobarcli" "$@"
  else
    swift run --package-path "$HOME/Projects/RepoBar" repobarcli "$@"
  fi
}

repobar_cmd status --json
```

Default owners for broad triage: `steipete`, `openclaw`. Do not include `amantus-ai` or other owners unless the user names them, the current repo is already under that owner, or the task explicitly asks for all/everything. For an exact owner-specific task, do not broaden beyond the named owner.

## Local Repo Gate

Before starting work inside any local project, verify the checkout is ready:

```bash
git status --short --branch
git branch --show-current
git pull --ff-only
git status --short --branch
```

Proceed only when the branch is `main`, the pull succeeds, and the worktree is clean. If the branch is not `main`, the pull fails, or `git status --short` shows changes, stop and ask Peter what to do. Do not switch branches, stash, commit, reset, restore, or clean without explicit direction.

## Scope Rule

If the user says `triage` and the current working directory is a Git repo with a GitHub remote, triage only that project. Do not broaden to all Peter/org queues unless the user says `broad`, `all`, `everything`, names multiple owners/orgs, or asks for cross-repo triage.

Find the current project:

```bash
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [ -z "$repo" ]; then
  url=$(git remote get-url origin 2>/dev/null || true)
  repo=$(printf '%s\n' "$url" |
    sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\\.git$##')
fi
printf '%s\n' "$repo"
```

Current-project triage starts with:

```bash
gh issue list --repo "$repo" --state open --limit 50 \
  --json number,title,author,labels,updatedAt,url
gh pr list --repo "$repo" --state open --limit 50 \
  --json number,title,author,isDraft,reviewDecision,mergeStateStatus,updatedAt,url
```

Then inspect selected items with `gh issue view`, `gh pr view`, `gh pr diff`, checks, and source/tests as needed. Only comment, close, merge, rerun, or patch with strong evidence.

## Fast Queue Map

Use this only when the scope is broad. Start with repo-level queue maps. This finds repos with open issues and/or PRs and gives counts.

PR queue, primary triage order:

```bash
repobar_cmd repos \
  --scope all \
  --only-with work \
  --owner steipete \
  --owner openclaw \
  --sort prs \
  --json
```

Issue pressure, second pass when issues matter:

```bash
repobar_cmd repos \
  --scope all \
  --only-with work \
  --owner steipete \
  --owner openclaw \
  --sort issues \
  --json
```

Use `--forks` and `--archived` only when the user says "all", "everything", or asks for archaeology. Default triage should omit forks and archived repos unless their queues are specifically relevant.

For a compact terminal view:

```bash
repobar_cmd repos --scope all --only-with work --owner steipete --owner openclaw --sort prs --plain
```

Useful `jq` summary:

```bash
repobar_cmd repos --scope all --only-with work --owner steipete --owner openclaw --sort prs --json |
  jq -r '.[] | [.fullName, .openIssues, .openPulls, .activityTitle, .activityActor] | @tsv'
```

When summarizing a PR-sorted queue, preserve RepoBar's PR-count order. Do not include a lower-PR repo while omitting a higher-PR repo from the same owner scope. Zero-issue repos with open PRs, for example `openclaw/crabbox`, are still triage-relevant.

## Detail Pass

After a broad queue map, inspect only the top repos unless the user explicitly wants exhaustive detail.

```bash
repobar_cmd issues <owner/name> --limit 50 --json
repobar_cmd pulls <owner/name> --limit 50 --json
repobar_cmd ci <owner/name> --limit 20 --json
repobar_cmd activity <owner/name> --limit 20 --json
```

For PRs that look mergeable or suspicious, switch to `gh` for maintainer-grade state:

```bash
gh pr view <n> --repo <owner/name> --json number,title,state,author,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup,updatedAt,url
gh pr diff <n> --repo <owner/name> --patch
gh run list --repo <owner/name> --branch <branch> --limit 10
```

For issues that may already be fixed, switch to `gh issue view`, then inspect current source before commenting or closing.

## Local Cross-Check

Use this when the task mentions local project state, dirty repos, or "what do I own here".

```bash
repobar_cmd local --root "$HOME/Projects" --depth 1 --limit 200 --plain
repobar_cmd local --root "$HOME/Projects" --depth 1 --sync --limit 200 --json
```

Do not run destructive local actions (`local reset`, branch deletes, checkout moves) unless the user explicitly asks.

## Triage Heuristics

Prioritize:

- PRs with green or nearly-green CI, recent maintainer activity, or low-risk dependency/docs/test changes.
- Repos with high open PR counts but recent activity, because they often hide obvious cleanup.
- Issues that are reproducible, recently reported, or block releases.
- Security, release, auth, install, CI, and data-loss reports before cosmetic items.

Deprioritize:

- Archived repos unless the user asked for them.
- Fork-only queues unless the fork is actively maintained by Peter.
- Old broad feature requests with no reproduction or owner signal.
- Repos with missing/removable remotes until local state is clarified.

## Output Shape

For a broad scan, answer with:

```text
Owners scanned: steipete, openclaw
Source: RepoBar <command summary>, plus gh for selected PRs/issues

Top queues:
- owner/repo: X issues, Y PRs; why it matters; next action

Immediate actions:
- <small obvious merge/fix/comment/rerun>

Needs judgment:
- <larger/ambiguous queues>

Skipped:
- archived/forks/missing access/etc.
```

When the user asks to act, keep going: inspect the selected PRs/issues with `gh`, rerun/fix CI, comment/close/merge only with evidence, and report exact commands/proof.
