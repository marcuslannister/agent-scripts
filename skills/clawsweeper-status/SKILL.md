---
name: clawsweeper-status
description: ClawSweeper status: recent closed/commented/reviewed/merged URLs, workflow health, active workers, compact ops snapshot.
---

# ClawSweeper Status

## Quick Start

Run the bundled status script first:

```bash
/Users/steipete/Projects/agent-scripts/skills/clawsweeper-status/scripts/clawsweeper-status.sh
```

Useful options:

```bash
# Last 10 hours for the default target repo, openclaw/openclaw
/Users/steipete/Projects/agent-scripts/skills/clawsweeper-status/scripts/clawsweeper-status.sh --hours 10

# A different target repo
/Users/steipete/Projects/agent-scripts/skills/clawsweeper-status/scripts/clawsweeper-status.sh --repo openclaw/clawhub

# More rows per activity section
/Users/steipete/Projects/agent-scripts/skills/clawsweeper-status/scripts/clawsweeper-status.sh --limit 15
```

## Output Contract

Report these sections concisely:

- `Workers`: active workflow count, queued/waiting count, active Codex job estimate, and active workflow groups.
- `Recently merged`: merged PR URLs plus one-line titles.
- `Recently reviewed`: ClawSweeper/Codex review comment URLs plus one-line comment summary.
- `Recently commented`: other recent ClawSweeper comment URLs plus one-line comment summary.
- `Recently closed`: closed issue/PR URLs plus one-line titles.

If the script returns no rows for a section, say `none found in window`.

## Efficient Data Sources

Prefer the script because it uses bounded API calls:

- one recent Actions runs page from `openclaw/clawsweeper`;
- one jobs page per active run to estimate live Codex jobs;
- recent issue comments for review/comment URLs;
- recent issue events for close URLs;
- recent closed PRs for merge URLs.

Do not browse the web for these checks. Use `gh` directly.

## Interpretation

- Cancelled repository-dispatch review runs are usually expected supersession when a newer event for the same item arrives.
- Count active Codex from in-progress/queued jobs whose names match review, commit review, repair, or worker execution lanes.
- Treat stale `gh run list` output cautiously; prefer `gh api repos/openclaw/clawsweeper/actions/runs?...` and per-run jobs when the numbers disagree.
- Use full GitHub URLs in the final answer.
