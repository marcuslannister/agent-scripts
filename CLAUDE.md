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

Root policy: each CLI reads exactly one skills root. Claude Code reads repo `skills/` (via `~/.claude/skills`); Codex reads only `~/.agents/skills` — never a `~/.codex/skills` symlink, which would make Codex load both roots and see duplicates. `scripts/update-skill-topology.sh` owns legacy-root hygiene and manifest-approved distribution.

Destination principle: skills both agents need → tracked in repo `skills/` and explicitly approved for Codex in `skill-topology.json`; skills only Codex needs → authored under `codex-skills/`. A skill Claude Code already gets as a plugin may use a Codex-only distribution mechanism.

1. Ships both Claude Code and Codex plugins (claude-mem, Waza) → each CLI's native plugin marketplace commands; no entries in `skills/`.
2. Ships a Claude Code plugin but no Codex plugin (visual-explainer) → Claude via plugin; Codex via the project's npx installer if it has one, otherwise clone under `~/Projects` and rsync a copy into `~/.agents/skills`; no entries in `skills/`.
3. npx-only skill repos (mattpocock/skills) → the manifest adapter installs the canonical Codex copies with `npx skills add … --agent codex`, then makes owned, gitignored Claude-side copies; never track them in `skills/`.
4. Source-only skill repos (khazix-skills, anthropics/skills) → clone under `~/Projects`, then rsync COPIES into the destination surface — never symlinks. Copies in `skills/` stay untracked via marker-delimited `.gitignore` blocks.
