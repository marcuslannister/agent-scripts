---
name: "github-project-triage"
description: "RepoBar GitHub queue triage: open issues/PRs across Peter profiles, orgs, local projects."
---

# GitHub Project Triage

Use RepoBar as the first pass for broad queue discovery. It is faster and more profile-aware than hand-rolling `gh repo list` loops, and it already understands Peter's repo activity, issue counts, PR counts, local projects, auth, cache, and filters.

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

Default owners for "my profiles": `steipete`, `amantus-ai`, `openclaw`. Add or remove owners based on the user's wording, local repo remotes, or the authenticated GitHub account. For an exact owner-specific task, do not broaden beyond the named owner.

## Fast Queue Map

Start with the repo-level queue map. This finds repos with open issues and/or PRs and gives counts.

```bash
repobar_cmd repos \
  --scope all \
  --only-with work \
  --owner steipete \
  --owner amantus-ai \
  --owner openclaw \
  --sort activity \
  --json
```

Use `--forks` and `--archived` only when the user says "all", "everything", or asks for archaeology. Default triage should omit forks and archived repos unless their queues are specifically relevant.

For a compact terminal view:

```bash
repobar_cmd repos --scope all --only-with work --owner steipete --owner amantus-ai --owner openclaw --plain
```

Useful `jq` summary:

```bash
repobar_cmd repos --scope all --only-with work --owner steipete --owner amantus-ai --owner openclaw --json |
  jq -r '.[] | [.fullName, .openIssues, .openPulls, .activityTitle, .activityActor] | @tsv'
```

## Detail Pass

After the queue map, inspect only the top repos unless the user explicitly wants exhaustive detail.

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
Owners scanned: steipete, amantus-ai, openclaw
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
