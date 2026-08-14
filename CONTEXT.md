# agent-scripts

Personal toolkit that installs and updates skills and plugins for multiple agent CLIs (Claude Code, Codex) from one repo.

## Language

### Distribution surfaces

**Claude surface**:
`~/.claude/skills` — Claude Code's single skills root. Reconciled per-skill copies selected by the skills matrix; owner markers protect unrelated entries.
_Avoid_: skills dir, shared folder, shared skills surface

**Codex surface**:
`~/.agents/skills` — Codex's single skills root. Assembled from canonical installs, source-specific copies, and Codex distribution exceptions.
_Avoid_: agents dir, Codex-only surface

**Codex distribution exception**:
An explicit, recorded decision to place a named skill or source on the Codex surface. Unknown sources require user decision; routine updates reuse recorded decisions.
_Avoid_: automatic mirror, default copy

### Source classification

**Repo-owned source**:
Skills tracked in this repo. The tracked `skills/` tree mirrors `steipete/agent-scripts:main` and defaults to Claude; `codex-skills/` entries default to Codex.

**Upstream mirror precedence**:
A tracked `skills/<name>/SKILL.md` owns that skill identity. Copy-source discovery omits the same name, so one skill cannot be distributed by both repo-owned and source-only classifications.

**Codex authoring source**:
The repo `codex-skills/` directory, not read by Claude. Holds repo-owned skills that target only Codex.
_Avoid_: Codex surface, Codex-only surface

**Foreign skill staging**:
The repo `other-skills/<owner>/` holding area, not an agent surface. Fully tracked; staged skills carry no copy markers — git history is their provenance and drift detection. Each source dir holds a tracked `.source.json` (upstream repo, commit SHA, sync time), written by acquire. Two-phase flow: acquire mirrors complete inventories into staging; distribute copies matrix-selected skills onward.
_Avoid_: Claude surface, Codex surface, automatic install, gitignored copy

**Acquire phase**:
`update-skill-topology.sh`. Network phase: refreshes upstream sources, mirrors complete inventories into tracked staging, reconciles native plugins, and applies verified dual-plugin duplicate cleanup owned by native-plugin policy. Selection-blind — never reads the skills matrix. The operator reviews, commits, and pushes staging changes.
_Avoid_: update step, fetch script

**Distribute phase**:
`agent-tooling/sync-skill-surfaces.sh`. Offline phase: reads the skills matrix directly, resolves selected names from tracked repo content, and reconciles both surfaces with one marker owner. It reads neither the topology manifest nor adapter registry. Unresolvable rows are reported after all resolvable work is applied.
_Avoid_: install script, deploy step

**Dual-plugin skill**:
A skill maintained by its authoritative upstream and exposed through both Claude Code's and Codex's native plugin systems. Classification and duplicate cleanup are scoped to the expected skill identity, not the repository; native install and reconcile happen per plugin bundle. Existing copies remain until one gate verifies both native paths, then every duplicate of only that skill is removed regardless of copy provenance.
_Avoid_: plugin-both, plugin-both repo, source-wide dual classification

**Native verification gate**:
The per-skill condition requiring both native plugins to be installed, enabled, current, and to expose the expected runtime skill. Duplicate copies stay present while the gate is pending or blocked; both are removed only after verification.
_Avoid_: plugin installed, bundle verified

**Plugin-managed recovery**:
Failure handling that preserves native plugins as the desired distribution mechanism. Allowed actions are upstream repair, native rollback, or a new explicit manifest decision; reconciliation never creates or recreates a fallback surface copy. The rule governs surface copies, not the source a native plugin installs from.
_Avoid_: automatic fallback, temporary copy

**Native-state repair**:
A direct write into another CLI's internal storage — Codex's marketplace snapshot under `~/.codex/.tmp`, its install metadata, or its `config.toml` marketplace fields. Rejected by ADR-0007 as tooling policy; the operator may do it by hand, but adapters reach that state only through `codex` commands.
_Avoid_: snapshot repair, in-place fetch fallback, marketplace fix-up

**Plugin-Claude-only repo**:
A repo shipping a Claude Code plugin but no Codex plugin; the Codex side is a tracked staged copy distributed like any source-only skill.

**npx-only repo**:
A skills-CLI-shaped source whose complete inventory is cloned and staged under `other-skills/matt/`. Destination-approved skills copy from staging to Codex; Matt reaches Claude through its separate plugin source. Legacy npx lock entries are reported as decision-required, never mutated.

**Source-only repo**:
A skill repo with no installer or plugin manifest. Its complete inventory stages under the matching `other-skills/<owner>/`; only destination-approved skills copy onward to agent surfaces.

### Install artifacts

**Canonical copy**:
The install treated as source of truth for a skill, from which other surfaces are synced.

**Untracked copy**:
A surface-resident skill directory rsynced from tracked repo content by distribute. Only surfaces hold untracked copies; staging is tracked.
_Avoid_: vendored copy, symlink

**Owner**:
The single surface-copy writer, `skill-matrix`, recorded on line 2 of `.agent-scripts-copy` (line 1 is the tracked source path and line 3 the sync-time hash). Markers exist only on surfaces; staging provenance stays in git and `.source.json`.
_Avoid_: adapter owner, source prefix, gitignore block

**Sync-time hash**:
Line 3 of the marker — a deterministic SHA-256 over the copy's non-hidden files, stamped by `install_skill_copy` at sync time (best-effort; omitted when no sha256 tool exists). Topology checks compare it to the current upstream source (→ upstream advanced) and to the on-disk copy (→ hand-edited locally), so drift in gitignored copies is detectable without a full re-sync. Surfaced by `sync-skill-surfaces.sh --check`.
_Avoid_: reusing it as an identity or cache key — it only answers "did content change since last sync".

**Topology manifest**:
`agent-tooling/skill-topology.json`, one entry per acquire-owned source. It records source ids, classifications, and default native/staging destinations. Distribution never reads it.

**Private adapter**:
An implementation under `agent-tooling/distribution-topology/adapters/`, registered exactly once and callable only by the topology module. It discovers and reconciles one manifest source without owning policy.

**Routine updater**:
`update-all.sh`. Four ordered steps: agent CLI updates, acquire, selection-preserving matrix regeneration, then distribute. It is review-first unless explicit Ship mode is selected.

**Ship mode**:
An explicit routine updater mode that validates and records refreshed tracked skill state, then commits and synchronizes it with the remote. It requires a clean starting state and never ships failed updates.
_Avoid_: automatic push, default shipping
