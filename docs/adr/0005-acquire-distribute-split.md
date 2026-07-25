---
status: accepted
---

# Acquire/distribute split with tracked staging

This ADR supersedes three ADR-0002 clauses: the sole-public-command rule, gitignored reproducible staging, and the two-step routine updater. Manifest-owned topology (ADR-0002), one root per CLI (ADR-0001/0004), and matrix-selected copies (ADR-0004) remain in force.

Skill distribution runs as two public phases. `update-skill-topology.sh` is the acquire phase: it refreshes upstream sources over the network, mirrors each skill-bearing source's complete inventory into tracked `other-skills/<owner>/` staging, and performs native plugin reconciliation. `agent-tooling/sync-skill-surfaces.sh` is the distribute phase: offline, it copies matrix-selected skills from tracked staging (plus repo-owned `skills/` and `codex-skills/`) to the Claude and Codex surfaces, removes orphans, and runs root hygiene. The routine updater becomes three ordered steps: agent CLI updates, acquire, distribute.

Acquire is selection-blind: it never reads the skills matrix. Distribute owns matrix parsing, validation against staged inventories, generated-override persistence in `skill-topology.json`, and matrix report regeneration.

Foreign skill staging is fully tracked. Staging gitignore blocks are removed; staged skills carry no `.agent-scripts-copy` markers — git history is their provenance and drift detection. Acquire writes one tracked `.source.json` per source recording upstream repo, commit SHA, and sync time. Surface copies remain marker-owned with staging as their recorded source. Acquire writes files only and never runs git; the operator reviews, commits, and pushes staging changes from the main machine, and secondary machines pull then distribute.

Every surface copy comes from tracked repo content, no exceptions: visual-explainer's Codex copy stages under `other-skills/nicobailon/` like any source-only skill while its Claude side stays native-plugin. The legacy npx removal mutation is deleted — the skills lock is observed empty; inspection still reports known-npx lock entries as decision-required rather than mutating them.

Distribute fails with a blocking error naming the acquire step when a matrix row selects a skill absent from staging. Staleness against upstream is never checked offline; staged content is authoritative as pulled (accepted staleness contract). Each command's `--check` previews only its own phase: acquire previews upstream drift, distribute previews surface drift.
