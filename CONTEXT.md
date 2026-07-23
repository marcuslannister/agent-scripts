# agent-scripts

Personal toolkit that installs and updates skills and plugins for multiple agent CLIs (Claude Code, Codex) from one repo.

## Language

### Distribution surfaces

**Claude surface**:
The repo `skills/` directory, read only by Claude Code (its user skill dir points at it). Default home for tracked repo skills; they do not flow into Codex unless recorded as a Codex distribution exception.
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
A repo shipping a Claude Code plugin but no Codex plugin; the Codex side is served by whatever the repo offers (installer or copy).

**npx-only repo**:
A skill repo distributed solely through a manifest-scoped skills CLI adapter (`npx skills add`). Generic global updates are not policy.

**Source-only repo**:
A skill repo with no installer or plugin manifest; cloned under `~/Projects` and copied into a surface.

### Install artifacts

**Canonical copy**:
The install treated as source of truth for a skill, from which other surfaces are synced.

**Untracked copy**:
A skill directory rsynced into a surface and kept out of git by a marker-delimited ignore block (`.gitignore` or repo-local `.git/info/exclude`). The repo tracks the script that produces it, not the content.
_Avoid_: vendored copy, symlink

**Owner**:
The private adapter reconciliation scope a copy belongs to, recorded on line 2 of the copy's `.agent-scripts-copy` marker (line 1 is the upstream source path, line 3 the sync-time content hash). Orphan cleanup keys on the owner, so several registered sources can share one surface without deleting each other's copies. A pre-owner copy with a single-line marker is left untouched until its adapter re-syncs it and stamps the owner.
_Avoid_: source prefix, gitignore block (the pre-owner ways ownership was inferred)

**Sync-time hash**:
Line 3 of the marker — a deterministic SHA-256 over the copy's non-hidden files, stamped by `install_skill_copy` at sync time (best-effort; omitted when no sha256 tool exists). Topology checks compare it to the current upstream source (→ upstream advanced) and to the on-disk copy (→ hand-edited locally), so drift in gitignored copies is detectable without a full re-sync. Surfaced by `update-skill-topology.sh --check`.
_Avoid_: reusing it as an identity or cache key — it only answers "did content change since last sync".

**Topology manifest**:
`skill-topology.json`, the only desired-distribution policy. One entry per skill-bearing source; source defaults plus named overrides declare destinations.

**Private adapter**:
An implementation under `scripts/distribution-topology/adapters/`, registered exactly once and callable only by the topology module. It discovers and reconciles one manifest source without owning policy.

**Routine updater**:
`update-all.sh`. Exactly two ordered steps: agent CLI updates, then skill-topology reconciliation.
