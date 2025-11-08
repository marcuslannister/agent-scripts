# Agent Scripts

This folder collects the Sweetistics guardrail helpers so they are easy to reuse in other repos or share during onboarding. Everything here is copied verbatim from `/Users/steipete/Projects/sweetistics` on 2025-11-08 unless otherwise noted.

## Runner Shim (`runner`, `scripts/runner.ts`)
- **What it is:** `runner` is the Bash entry point that forces commands through Bun and `scripts/runner.ts`. The Bun runner enforces timeout tiers, intercepts risky commands (git/rm/find), auto-prompts for tmux handoffs, and ensures cleanup logs stay consistent across repos.
- **AGENTS.md rules:**  
  - “Run all commands through `./runner <command>` ... skip only for read-only inspection tools.” (AGENTS.md:50)  
  - “When I type ‘rebase,’ … keep using `./runner git …` (or `./git …`) so the guardrails stay active.” (AGENTS.md:189)  
  - “When you run the allowed git commands, invoke them through the wrapper (e.g., `./runner git status -sb`).” (AGENTS.md:190)

## Git Shim (`git`, `bin/git`, `scripts/git-policy.ts`)
- **What it is:** Bun-based drop-in replacement for git that analyzes the invocation, blocks destructive subcommands, and requires either the committer helper or explicit consent environment variables. `scripts/git-policy.ts` houses the heuristics.
- **AGENTS.md rules:**  
  - “IMPORTANT! ALL git commands are forbidden ... the only git CLI commands you may run are `git status`, `git diff`, and `git log`; run `git push` only when I explicitly ask for it.” (AGENTS.md:181-184)  
  - “When I type ‘rebase,’ treat it as consent ... Keep using `./runner git …` (or `./git …` if you absolutely must) so the guardrails stay active.” (AGENTS.md:189)

> Heads-up: the shim still imports `@/lib/utils/to-array`. In repos without that alias, replace the import with a local helper.

## Committer Helper (`scripts/committer`)
- **What it is:** Bash helper that stages exactly the files you list, enforces non-empty commit messages, and creates the commit (used because direct `git add`/`git commit` is blocked).
- **AGENTS.md rules:**  
  - “IMPORTANT! To create a commit, use `./scripts/committer "your commit message" "path/to/file1" "path/to/file2"` ... never run `git add` yourself.” (AGENTS.md:192)

## Docs Lister (`scripts/docs-list.ts`)
- **What it is:** tsx script that walks `docs/`, enforces front-matter (`summary`, `read_when`), and prints the summaries surfaced by `pnpm run docs:list`. Other repos can wire the same command into their onboarding flow.
- **AGENTS.md rules:**  
  - “Non-negotiable: run `pnpm run docs:list`, read the summaries, and open the referenced rule files before you write a single line of code.” (AGENTS.md:72)  
  - “Start every session with `pnpm run docs:list` ... keep the relevant docs open while you implement.” (AGENTS.md:77)  
  - “Add `read_when` hints to key docs so `pnpm docs:list` surfaces them when the topic is relevant.” (AGENTS.md:81)

## Guardrail Expectations
For any change to these helpers—runner, git shim, committer, docs lister—log the update for fellow agents:

```
./scripts/committer "docs: update AGENTS for runner" "AGENTS.md"
```

Use a different commit message (“docs: update AGENTS for git shim”, etc.) when appropriate, but always note the behavior change in `AGENTS.md`.
