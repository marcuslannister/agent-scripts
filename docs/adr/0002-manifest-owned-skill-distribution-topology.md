---
status: accepted
---

# Manifest-owned skill distribution topology

This ADR supersedes ADR-0001's bulk repo-skill publication consequence while retaining its one-active-skills-root decision.

All skill-bearing sources are governed by repo-tracked `skill-topology.json`, resolved by one private Bash topology core before any distribution mutation. The public topology command does not invoke or require Node. Repo-owned skills under `skills/` default to Claude and reach Codex only through explicit named exceptions; Codex-only repo skills live under `codex-skills/`, while source defaults plus per-skill overrides record every destination and unknown sources or collisions require user decision. Root hygiene remains routine but separate from publication; per-source updaters become private adapters, generic update-all/plugin/npx mirrors are removed, and one executable policy restores locality across both surfaces.

Global instruction pointers are setup state, not distribution policy. `setup-agent-instructions.sh` manages them only when explicitly invoked; topology reconciliation never calls it.

The routine updater performs only agent CLI updates, then topology reconciliation. `update-skill-topology.sh` is the sole public skill/plugin distribution command; source mechanics are private registered adapters. Old bulk repo publication, generic plugin/npx mutation, `find-skills` bootstrap, and all per-source public commands are removed without aliases or shims. The repository verifier rejects their return and requires a one-to-one manifest/adapter handshake.

Dual-plugin ownership is per expected skill. The authoritative upstream owns skill content; the manifest owns desired distribution; the private adapter owns native mechanics. Reconciliation works at plugin-bundle scope, then gates cleanup per skill: both native plugins must be installed, enabled, current, and expose that expected runtime skill before either duplicate copy is removed.

Desired dual-plugin topology remains plugin-managed during marketplace outages, omitted or withdrawn skills, later plugin regressions, and cleanup failures. Reconciliation never creates or recreates fallback copies. The JSON policy object is scoped to dual-plugin migrations; other source classifications retain their manifest-owned distribution mechanisms. Reports expose native reconciliation, runtime verification, copy retention, copy removal, and blocking failures as separate events. Recovery is limited to upstream repair, native rollback, or a new explicit manifest decision; no failure implicitly changes the distribution mechanism. A repeated healthy reconciliation is clean and idempotent.
