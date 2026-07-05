# agent-scripts

Personal toolkit that installs and updates skills and plugins for multiple agent CLIs (Claude Code, Codex) from one repo.

## Language

### Distribution surfaces

**Shared skills surface**:
The repo `skills/` directory, read by both Claude Code and Codex (their user skill dirs point at it). Skills both agents need live here.
_Avoid_: skills dir, shared folder

**Codex-only surface**:
`~/.agents/skills` — read only by Codex. Holds skills Claude Code must not see (usually because Claude already gets them as a plugin).
_Avoid_: agents dir

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

**Updater**:
A per-source script in `scripts/` that brings one repo's skills/plugins to their desired state; `update-all.sh` orchestrates all of them.
