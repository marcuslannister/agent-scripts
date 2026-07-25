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
`update-skill-topology.sh`. Network phase: refreshes upstream sources, mirrors complete inventories into tracked staging, reconciles native plugins. Selection-blind — never reads the skills matrix. Writes files only; the operator commits and pushes.
_Avoid_: update step, fetch script

**Distribute phase**:
`agent-tooling/sync-skill-surfaces.sh`. Offline phase: owns the skills matrix (validation, generated overrides, report), copies selected skills from tracked repo content to both surfaces, removes orphans, runs root hygiene. Never touches the network; a matrix row without staged content is a blocking error naming acquire.
_Avoid_: install script, deploy step

**Dual-plugin skill**:
A skill maintained by its authoritative upstream and exposed through both Claude Code's and Codex's native plugin systems. Classification and duplicate cleanup are scoped to the expected skill identity, not the repository; native install and reconcile happen per plugin bundle. Existing copies remain until one gate verifies both native paths, then every duplicate of only that skill is removed regardless of copy provenance.
_Avoid_: plugin-both, plugin-both repo, source-wide dual classification

**Native verification gate**:
The per-skill condition requiring both native plugins to be installed, enabled, current, and to expose the expected runtime skill. Duplicate copies stay present while the gate is pending or blocked; both are removed only after verification.
_Avoid_: plugin installed, bundle verified

**Plugin-managed recovery**:
Failure handling that preserves native plugins as the desired distribution mechanism. Allowed actions are upstream repair, native rollback, or a new explicit manifest decision; reconciliation never creates or recreates a fallback copy.
_Avoid_: automatic fallback, temporary copy

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
The private adapter reconciliation scope a copy belongs to, recorded on line 2 of the copy's `.agent-scripts-copy` marker (line 1 is the tracked-staging source path, line 3 the sync-time content hash); markers exist only on surface copies. Orphan cleanup keys on the owner, so several registered sources can share one surface without deleting each other's copies. A pre-owner copy with a single-line marker is left untouched until its adapter re-syncs it and stamps the owner.
_Avoid_: source prefix, gitignore block (the pre-owner ways ownership was inferred)

**Sync-time hash**:
Line 3 of the marker — a deterministic SHA-256 over the copy's non-hidden files, stamped by `install_skill_copy` at sync time (best-effort; omitted when no sha256 tool exists). Topology checks compare it to the current upstream source (→ upstream advanced) and to the on-disk copy (→ hand-edited locally), so drift in gitignored copies is detectable without a full re-sync. Surfaced by `sync-skill-surfaces.sh --check`.
_Avoid_: reusing it as an identity or cache key — it only answers "did content change since last sync".

**Topology manifest**:
`agent-tooling/skill-topology.json`, one entry per skill-bearing source. `Type: skill` overrides are marked generated blocks derived from `agent-tooling/skills-matrix.md` by the distribute phase; plugin bundle policy and source defaults remain hand-maintained manifest content. An empty generated override selects no agent surface while preserving staged content.

**Private adapter**:
An implementation under `agent-tooling/distribution-topology/adapters/`, registered exactly once and callable only by the topology module. It discovers and reconciles one manifest source without owning policy.

**Routine updater**:
`update-all.sh`. Exactly three ordered steps: agent CLI updates, then acquire, then distribute.
