---
status: superseded by ADR-0002
---

# One skills root per CLI

Codex used to read both `~/.agents/skills` and the repo `skills/` dir (through a `~/.codex/skills` symlink), so every skill synced from the Codex surface into the Claude surface loaded twice. We decided each CLI reads exactly one root: Claude Code reads repo `skills/` via `~/.claude/skills`; Codex reads only `~/.agents/skills`. ADR-0002 retains that one-root decision but replaces this ADR's bulk `update-repo-skills.sh` publication consequence with manifest-owned topology reconciliation; the old command is deleted.

## Considered options

- **Split the shared root**: keep `skills/` tracked-only and give Claude its own script-populated root. Rejected — Claude would read copies exactly where skills are authored, losing live-edit locality in the CLI used to iterate on them.
- **Dedupe by deleting duplicates from `~/.agents/skills`**: rejected — that directory is the skills CLI's canonical store; deletions break its lock and are recreated on the next run.

## Consequences

- Codex sees repo-skill edits only after topology reconciliation (accepted staleness contract; Claude stays live).
- An independent topology hygiene step moves the old `~/.codex/skills` symlink or any non-system entries beside its `.system` dir into `~/.codex/skills-migrated-<timestamp>`, so a machine in the old topology gets a reversible cleanup instead of silent double-loading. Codex's own bundled system skills under `~/.codex/skills/.system` are tolerated — the CLI recreates that dir itself.
- Marker-scoped orphan cleanup removes Codex-surface copies whose tracked source was deleted or renamed.
- CLI-specific skill forks are unified into one CLI-agnostic tracked skill rather than deny-listed (first case: `review-claudemd`).
