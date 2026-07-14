---
status: accepted
---

# Manifest-owned skill distribution topology

This ADR supersedes ADR-0001's bulk repo-skill publication consequence while retaining its one-active-skills-root decision.

All skill-bearing sources are governed by repo-tracked `skill-topology.json`, resolved by one private Bash topology core before any distribution mutation. The public topology command does not invoke or require Node. Repo-owned skills under `skills/` default to Claude and reach Codex only through explicit named exceptions; Codex-only repo skills live under `codex-skills/`, while source defaults plus per-skill overrides record every destination and unknown sources or collisions require user decision. Root hygiene remains routine but separate from publication; per-source updaters become private adapters, generic update-all/plugin/npx mirrors are removed, and one executable policy restores locality across both surfaces.

Global instruction pointers are setup state, not distribution policy. `setup-agent-instructions.sh` manages them only when explicitly invoked; topology reconciliation never calls it.

The routine updater performs only agent CLI updates, then topology reconciliation. `update-skill-topology.sh` is the sole public skill/plugin distribution command; source mechanics are private registered adapters. Old bulk repo publication, generic plugin/npx mutation, `find-skills` bootstrap, and all per-source public commands are removed without aliases or shims. The repository verifier rejects their return and requires a one-to-one manifest/adapter handshake.
