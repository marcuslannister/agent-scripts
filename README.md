# Agent Scripts

This folder collects the Sweetistics guardrail helpers so they are easy to reuse in other repos or share during onboarding. Everything here is copied verbatim from `/Users/steipete/Projects/sweetistics` on 2025-11-08.

## What's Included
- `runner`: Bash shim that funnels every command through Bun + `scripts/runner.ts`.
- `scripts/runner.ts`: The Bun runner implementation (timeouts, git policy enforcement, trash safety, tmux escalation hints).
- `scripts/committer`: Helper that stages an explicit file list and creates a commit under restricted workflows.
- `git`, `bin/git`, `scripts/git-policy.ts`: The git blocker shim that refuses unsafe commands and forces the committer helper unless the user explicitly opted in. (These files still import `@/lib/utils/to-array`; in other repos you'll need to replace that alias with a local helper.)

## AGENTS.md Expectations
Whenever you change any of these guardrails inside Sweetistics (or another repo using the same protocol), make sure the tweak is documented for fellow agents. The canonical workflow is:

```
./scripts/committer "docs: update AGENTS for runner" "AGENTS.md"
```

Drop a concise note explaining what changed and why. If you clone these guardrails into another project, keep a similar playbook so contributors understand how to use the runner, committer, and git blocker.
