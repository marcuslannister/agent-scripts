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

Start from a clean checkout. Restore every implementation-owned path from the
pre-mirror baseline. The rollback guide itself stays present:

```bash
git status -sb
git restore --source=560183d190cdbb8b629e07f2eead0aec362bd782 \
  --staged --worktree -- \
  CHANGELOG.md CONTEXT.md INDEX.md README.md \
  codex-skills/maintainer-orchestrator \
  scripts/distribution-topology/adapters/copy-source.sh \
  scripts/test-maintainer-orchestrator-policy \
  skill-authors.json skill-topology.json skills \
  tests/maintainer-orchestrator-policy-test.sh \
  tests/skill-index-test.sh \
  tests/update-copy-distributed-topology-test.sh \
  tests/update-skill-topology-test.sh
```

Recreate the ignored source-owned copies through the restored reconciler policy.
Do not restore them from an arbitrary filesystem backup:

```bash
agent-tooling/update-skill-topology.sh
```

Verify the recovered layout, then commit the rollback:

```bash
agent-tooling/validate-skills
agent-tooling/generate-skill-index.sh --check
bash tests/update-skill-topology-test.sh
bash tests/update-copy-distributed-topology-test.sh
git diff --check
git status -sb
git commit -m "revert: restore pre-mirror skill layout"
```
