# agent-scripts — project rules

Project-scoped file. Root `AGENTS.MD` here is the shared global rules file (symlinked into `~/.claude` / `~/.codex`), not this repo's — repo-specific config goes in this file.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (marcuslannister/agent-scripts) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
