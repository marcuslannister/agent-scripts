---
status: accepted
---

# Staging-only tooling with user-managed native plugins

The topology engine and its private-adapter protocol (~3,550 lines serving nine fixed sources) existed mostly to reconcile native plugins, and measured routine runs spent 97% of their phase-3 time in one Codex marketplace call that can never succeed (ADR-0007). We cut native plugin management from tooling scope instead of rewriting it. The acquire phase becomes a staging-only command in the distribute phase's direct-script shape: refresh cached upstream source clones, mirror each source's complete skill inventory into tracked `other-skills/<owner>/` staging, write `.source.json`, and report drift in the same simple document form distribute uses. The engine (`topology.sh`, `schema.sh`, `report.sh`, `state.sh`) and the adapter protocol are deleted, not rewritten.

The topology manifest and the adapter registry duplicated the same source list and were cross-checked at runtime; they merge into one tracked sources list, `agent-tooling/sources.json`: id, classification, destinations, and a small `plugin` block kept only for the plugin refresh helper, `repair-codex-registry.sh`, and matrix reporting. A plugin marketplace whose native refresh is a permanent failure carries `"codexUpgrade": "manual"`, citing ADR-0007.

Native plugins are per-machine CLI state, installed and repaired by the operator through native commands — like the CLIs themselves. The routine path runs `update-plugins.sh`, a best-effort helper that invokes the native update commands, honors manual-upgrade markers, reports each failure in one line, and never fails the run. The dual-plugin native verification gate and its migration machinery are retired: their one-time duplicate cleanup completed on every machine that mattered, and recovery is upstream repair or native reinstall by hand. Unchanged from ADR-0002/0007: tooling never creates or recreates a surface copy to substitute for a broken plugin.

Commands settle at one per machine. `update-all.sh` (main machine) ships by default — fast-forward pull, agent CLI updates, staging acquire, selection-preserving matrix regeneration, distribute, then verify, commit, push; `--no-ship` keeps a review-only run. `update-local.sh` (every other machine, including Windows under Git Bash) fast-forward pulls, updates CLIs, runs the plugin helper, and distributes; `jq` and `rg` are documented one-time prerequisites on Windows. The legacy `scripts/sync-skills` symlink updater is retired to a refusing stub — it predates ADR-0004 and its whole-root symlinks would make distribute refuse the surfaces it created. The path itself stays present because ADR-0008 forbids deleting an upstream path; only its body is replaced.

This supersedes ADR-0002's private topology core, one-to-one manifest/adapter handshake, manifest artifact, and dual-plugin gating clauses; ADR-0005's clauses placing native plugin reconciliation and `--plugins-only` inside acquire; and ADR-0006's retained-manifest and acquire-adapter descriptions. Still in force: ADR-0001's one root per CLI, ADR-0004/0006's matrix-owned marker-protected surface copies, ADR-0005's two-phase acquire/distribute split with tracked staging, ADR-0007's rejection of broad native-state repair with its explicit claude-mem marker exception, and ADR-0008's upstream-complete overlay.

## Considered options

A faithful rewrite preserving plugin reconciliation behind the same external interface was designed first and rejected: nearly everything it would faithfully preserve — the gate machinery, the event/document schema, `plugin-both.sh` — exists to serve plugin management. ADR-0007's three refresh options for the oversized claude-mem marketplace (adapter-owned local marketplace, dropping the Codex destination, accepting ~21 minutes per run) all dissolve once the routine path stops attempting marketplace operations.

## Consequences

Routine runs drop from ~22 minutes to an expected 1–2 minutes on the main machine (1,286s of a measured 1,327s phase was the one doomed upgrade), and abandoned Codex marketplace staging directories stop accumulating because no failing marketplace operation launches on every run. The cost: plugin updates are no longer verified — a stale or broken plugin is discovered by its user, not by the updater. `repair-codex-registry.sh` remains the operator tool for Codex registry desync, reading its plugin metadata from the merged sources list.
