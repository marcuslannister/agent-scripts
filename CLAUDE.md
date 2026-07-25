# agent-scripts — project rules

Project-scoped file. Root `AGENTS.MD` here is the shared global rules file (symlinked into `~/.claude` / `~/.codex`), not this repo's — repo-specific config goes in this file.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (marcuslannister/agent-scripts) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Plugin & skill update rules

Root policy: each CLI reads exactly one skills root. Claude Code reads only `~/.claude/skills`; Codex reads only `~/.agents/skills`. `agent-tooling/update-skill-topology.sh` (acquire: network → tracked `other-skills/` staging + native plugins) and `agent-tooling/sync-skill-surfaces.sh` (distribute: staging → both roots, offline, owns the matrix) reconcile both roots as marker-owned, matrix-selected per-skill copies (ADR-0005). Never create a whole-tree skills symlink or a `~/.codex/skills` symlink.

Destination principle: every `Type: skill` row in `agent-tooling/skills-matrix.md` independently selects Claude and Codex copies; distribute generates its marked `agent-tooling/skill-topology.json` overrides. `Type: plugin` rows are report-only. Repo-owned skills live under `skills/` or `codex-skills/`; foreign skill inventories stage tracked under `other-skills/` before selection.

1. Ships both Claude Code and Codex plugins (claude-mem, Waza) → each CLI's native plugin marketplace commands; no entries in `skills/`.
2. Ships a Claude Code plugin but no Codex plugin (visual-explainer) → Claude via plugin; Codex via a tracked staged copy under `other-skills/`, distributed by `sync-skill-surfaces.sh`; no entries in `skills/`.
3. npx-only skill repos (mattpocock/skills) → stage tracked under `other-skills/` for matrix-selected Codex copies; Claude uses its separate plugin source; never track them in `skills/`.
4. Source-only skill repos (khazix-skills, anthropics/skills) → stage tracked under `other-skills/`, then distribute selected copies into each destination surface — never symlinks.
