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

### Instruction pointers

**Instruction pointer**:
A path each agent CLI reads its global rules from, created by `setup-agent-instructions.sh` only when explicitly invoked. Setup state, not distribution policy (ADR-0002/0010): the routine updater never creates or refreshes one. Claude Code reads `~/.claude/CLAUDE.md` plus `~/.claude/rules`; Codex reads `~/.codex/AGENTS.md`.
_Avoid_: instruction symlink, global config, agent surface

**Topic rules**:
The repo `rules/` directory, one file per subject, linked from `AGENTS.MD` as `~/.claude/rules/<name>.md`. The single editable source for everything outside the root hard rules. A repo-relative link resolves against the agent's cwd and breaks outside this checkout, so links stay home-relative.
_Avoid_: docs, rule modules, split instructions

**Generated Codex instructions**:
Tracked `AGENTS.codex.md`: `AGENTS.MD` with every topic rule inlined, built by `build-codex-instructions.sh`. Codex has no import syntax and does not open a file it is only linked to, so it needs one flat file. Tracking it means a pull refreshes it and no install lifecycle can go stale (ADR-0010); `--check` fails on drift. Build stages into a temp file and swaps on success, so a failed build cannot truncate the artifact into a false-green check.
_Avoid_: flattened copy, snapshot, generated pointer

**Pointer migration**:
Replacing an installer-owned predecessor at an instruction pointer. Only a symlink whose resolved target proves setup wrote it is replaced. A regular file is reported and left alone, because nothing distinguishes it from operator-authored rules. Foreign symlinks, including dangling ones, are always preserved.
_Avoid_: repair, overwrite, reinstall

### Source classification

**Upstream-complete overlay**:
The repository root contains every path from the recorded `steipete/agent-scripts:main` commit. Local paths and local modifications can coexist, but an upstream path cannot be absent.
_Avoid_: full mirror, exact mirror, vendored upstream

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
`update-skill-topology.sh`. Network phase: refreshes cached upstream source clones and mirrors complete inventories into tracked staging. Selection-blind — never reads the skills matrix — and performs no native plugin operations (ADR-0009). The operator reviews, commits, and pushes staging changes.
_Avoid_: update step, fetch script, plugin reconcile step

**Distribute phase**:
`agent-tooling/sync-skill-surfaces.sh`. Offline phase: reads the skills matrix directly, resolves selected names from tracked repo content, and reconciles both surfaces with one marker owner. It reads only the matrix and tracked repository content. Unresolvable rows are reported after all resolvable work is applied.
_Avoid_: install script, deploy step

**Plugin source**:
A sources-list entry describing a native plugin (name, repo, marketplaces). Read only by the plugin refresh helper, `repair-codex-registry.sh`, and matrix reporting; the plugins themselves are per-machine CLI state the operator installs and repairs through native commands. Tooling never creates a surface copy to substitute for a broken plugin.
_Avoid_: dual-plugin skill, managed plugin, plugin reconciliation

**Native-state repair**:
A direct write into another CLI's internal storage — Codex's marketplace snapshot under `~/.codex/.tmp`, its install metadata, or its `config.toml` marketplace fields. Rejected by ADR-0007 as tooling policy; all repair reaches state only through `codex` commands.
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

**Sources list**:
`agent-tooling/sources.json`, the one tracked list of skill-bearing sources: id, classification, destinations, and an optional plugin block. A plugin marketplace that cannot refresh natively carries a manual-upgrade marker citing ADR-0007. Distribution never reads it.
_Avoid_: topology manifest, adapter registry

**Codex registry desync**:
The state where Codex's marketplace and installed-plugin records disagree with its own on-disk snapshots: `plugin marketplace list` reports an entry as absent while `plugin marketplace add` refuses it as already added from a different source. Repaired by the operator with `repair-codex-registry.sh --fix`, which re-registers through `codex` commands only.
_Avoid_: missing marketplace, broken plugin, native-state repair

**Source clone cache**:
`~/.cache/agent-scripts/source-clones/<sourceId>`, one shallow clone of a read-only upstream repository per source. Reconcile refreshes it in place and discards it whenever the remote or the checkout is unusable. It is per-machine state that git never carries and that holds no local edits. Check mode never writes it — a preview clones into its own discovery root instead.
_Avoid_: staging, snapshot, local marketplace

**Routine updater**:
`update-all.sh`. Six ordered steps: fast-forward pull, agent CLI updates, plugin refresh, acquire, selection-preserving matrix regeneration, then distribute. It ships by default; `--no-ship` selects a review-only run. Only the plugin refresh is non-fatal.

**Ship mode**:
The routine updater's default closeout: validate and record refreshed tracked skill state, then commit and synchronize it with the remote. It requires a clean starting state and never ships failed updates; `--no-ship` opts out.
_Avoid_: separate release step, manual-only push

**Plugin refresh helper**:
`update-plugins.sh`. Best-effort native plugin updates on every machine: runs the native update commands, honors manual-upgrade markers (ADR-0007), reports each failure in one line, and never fails the run.
_Avoid_: plugin reconcile, verification gate
