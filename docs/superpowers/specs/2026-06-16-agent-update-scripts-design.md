# Agent Update Scripts — Design

Date: 2026-06-16

## Goal

zsh helpers to update the local coding-agent CLIs and Claude Code plugins in
one command. Keep the existing `scripts/update-cc-plugins.sh` (plugins) as-is;
add agent-CLI updating and a top-level orchestrator.

## Scope

- **In:** update Claude Code CLI, update Codex CLI, orchestrate both + existing
  plugin script.
- **Out:** Codex has no Claude-style plugin system — only its CLI is updated.
  No npm install of `@anthropic-ai/claude-code` (Claude is a native install,
  self-updates via `claude update`).

## Environment (verified)

- `claude` — native install at `~/.local/bin/claude`; self-updates via
  `claude update`.
- `codex` — npm package `@openai/codex` (currently `0.137.0`); npm global prefix
  `~/.local/npm-global`. Updates via `npm install -g @openai/codex`.

## Files & layout

All under `scripts/`.

| File | Role | Mechanism |
|------|------|-----------|
| `update-agents.zsh` | Update both CLIs: Claude + Codex | `claude update`, then `npm install -g @openai/codex` |
| `update-cc-plugins.sh` | **Existing, untouched** | Claude marketplaces + plugins |
| `update-all.zsh` | Top-level orchestrator | Calls `update-agents.zsh` → `update-cc-plugins.sh` |

### `update-agents.zsh`

- `#!/usr/bin/env zsh`, `set -euo pipefail`.
- Shared `info()` / `section()` colored output helpers matching the style of
  `update-cc-plugins.sh` (GREEN `==>`, YELLOW `>>>`).
- For each CLI: print current version, run update, print new version.
- Standalone-runnable.

### `update-all.zsh`

- `#!/usr/bin/env zsh`, `set -uo pipefail` (not `-e` — must survive a failing
  step to run the rest).
- Resolves its own dir so it can call sibling scripts regardless of cwd.
- Invokes `update-agents.zsh`, then `update-cc-plugins.sh`.

## Error handling

Run-all, then report (agreed). No fail-fast.

- **Orchestrator:** if any step fails, continue with the remaining steps.
  Collect per-step pass/fail. Print a final summary
  (e.g. `✓ agents / ✗ plugins`). Exit non-zero if any step failed.
- **`update-agents.zsh`:** try both CLIs even if one fails; report both; exit
  non-zero on any failure.

## Data flow

```
update-all.zsh
  ├─ update-agents.zsh
  │    ├─ claude update
  │    └─ npm install -g @openai/codex
  └─ update-cc-plugins.sh   (existing)
       ├─ claude plugin marketplace update
       └─ claude plugin update <each>
final: summary line, non-zero exit if anything failed
```

## Testing / verification

- Run `update-all.zsh`; confirm both CLIs report a version and plugins update.
- Simulate a failing step (e.g. temporarily bad package name) and confirm the
  orchestrator continues and the summary + non-zero exit are correct.
- `chmod +x` the two new scripts.

## Out of scope / YAGNI

- No flags/config, no dry-run, no scheduling. Plain sequential updaters.
