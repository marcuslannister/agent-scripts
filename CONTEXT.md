# agent-scripts

Personal toolkit that installs and updates skills and plugins for multiple agent CLIs (Claude Code, Codex) from one repo.

## Language

### Distribution surfaces

**Claude surface**:
The repo `skills/` directory, read only by Claude Code (its user skill dir points at it). Also the authoring home for repo-owned skills, from which the Codex surface is synced.
_Avoid_: skills dir, shared folder, shared skills surface

**Codex surface**:
`~/.agents/skills` — Codex's single skills root. Assembled from canonical installs, synced repo-owned skills, and Codex-only copies (skills Claude Code must not see, usually because Claude already gets them as a plugin).
_Avoid_: agents dir, Codex-only surface

### Source classification

**Plugin-both repo**:
A repo shipping plugin manifests for both Claude Code and Codex; managed by each CLI's native marketplace commands, never by copies.

**Plugin-Claude-only repo**:
A repo shipping a Claude Code plugin but no Codex plugin; the Codex side is served by whatever the repo offers (installer or copy).

**npx-only repo**:
A skill repo distributed solely through the skills CLI (`npx skills add`).

**Source-only repo**:
A skill repo with no installer or plugin manifest; cloned under `~/Projects` and copied into a surface.

### Install artifacts

**Canonical copy**:
The install treated as source of truth for a skill, from which other surfaces are synced.

**Untracked copy**:
A skill directory rsynced into a surface and kept out of git by a marker-delimited `.gitignore` block. The repo tracks the script that produces it, not the content.
_Avoid_: vendored copy, symlink

**Owner**:
The updater a copy belongs to, recorded on line 2 of the copy's `.agent-scripts-copy` marker (line 1 is the upstream source path). Orphan cleanup keys on the owner, so several updaters can share one surface without deleting each other's copies. A pre-owner copy with a single-line marker is left untouched until its own updater re-syncs it and stamps the owner.
_Avoid_: source prefix, gitignore block (the pre-owner ways ownership was inferred)

**Updater**:
A per-source script in `scripts/` that brings one repo's skills/plugins to their desired state; `update-all.sh` orchestrates all of them.
