---
status: accepted
---

# The own skills stage in `other-skills/marcus/`

This ADR supersedes the own-skills part of ADR-0013. The global rules stay in `global/`.

The own skills (`anvil-advanced-ops`, `architect`, `context-audit`, `herdr-coordinator`) moved from `global/skills/` to `other-skills/marcus/`. The skills matrix now selects them, and distribute copies them with markers, like every other staged skill. `global/bin/install-skills.sh` and its test are deleted, and `update-all.sh` and `update-local.sh` lost their best-effort "own skills" step.

Reason: `install-skills.sh` wrote unmarked copies, so every sync warned about them, and a second copy path did the same job as distribute.

## Consequences

- `marcus` has no `sources.json` entry, so acquire never stages into it and never prunes it. Edit the skills in place.
- The matrix shows the source as `marcus` with no repo URL, like `metrixbar`.
- A manual-only skill keeps `agents/openai.yaml` (`allow_implicit_invocation: false`) in its source folder. Distribute does not generate it, as `install-skills.sh` did.
- `check-agent-setup.sh` lost check 4 (the own skills). Distribute reports copy drift.
- Distribute takes over the existing unmarked copies, because their `SKILL.md` matches the source (`copy_is_adoptable`).
