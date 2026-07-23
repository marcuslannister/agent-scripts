---
summary: "Restore the skills tree that preceded the upstream mirror"
read_when:
  - Rolling back the steipete/agent-scripts skills mirror.
  - Recovering the former tracked and reconciler-owned skills layout.
---

# Upstream Skills Mirror Rollback

The upstream mirror replaced `skills/` at pre-mirror commit
`560183d190cdbb8b629e07f2eead0aec362bd782`. The ignored third-party copies
removed during the cutover remain reproducible from their registered sources.

Start from a clean checkout. Restore the former tracked tree and the former
Codex authoring copy:

```bash
git status -sb
git restore --source=560183d190cdbb8b629e07f2eead0aec362bd782 \
  --staged --worktree -- skills codex-skills/maintainer-orchestrator
```

Recreate the ignored source-owned copies through the reconciler. Do not restore
them from an arbitrary filesystem backup:

```bash
scripts/update-skill-topology.sh
```

Verify the recovered layout before committing the rollback:

```bash
scripts/validate-skills
scripts/generate-skill-index.sh --check
bash tests/update-skill-topology-test.sh
bash tests/update-copy-distributed-topology-test.sh
git status -sb
```
