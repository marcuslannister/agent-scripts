---
status: accepted
---

# Manifest-owned skill distribution topology

All skill-bearing sources are governed by repo-tracked `skill-topology.json`, resolved by one topology module before any distribution mutation. Repo-owned skills under `skills/` default to Claude and reach Codex only through explicit named exceptions; Codex-only repo skills live under `codex-skills/`, while source defaults plus per-skill overrides record every destination and unknown sources or collisions require user decision. Root hygiene remains routine but separate from publication; per-source updaters become private adapters, generic update-all/plugin/npx mirrors are removed, and one executable policy restores locality across both surfaces.

Global instruction pointers are setup state, not distribution policy. `setup-agent-instructions.sh` manages them only when explicitly invoked; topology reconciliation never calls it.
