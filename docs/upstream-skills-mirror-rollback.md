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

Start from a clean checkout. Revert all four mirror implementation commits without
committing yet; this restores the former tracked tree, topology policy, tests,
and Codex authoring copy together:

```bash
git status -sb
git revert --no-commit \
  50a56052ef3a3567e5a2a6cad2a6d5c8b1c15eeb \
  9d0bfb0e4be07853b17de64722a12dea9096d534 \
  c96b5f8608166054c4afdbceaa1f11838de424a4 \
  dd2fdd271bae97e5f862e5631e550fe65076b696
```

Recreate the ignored source-owned copies through the restored reconciler policy.
Do not restore them from an arbitrary filesystem backup:

```bash
scripts/update-skill-topology.sh
```

Verify the recovered layout, then commit the rollback:

```bash
scripts/validate-skills
scripts/generate-skill-index.sh --check
bash tests/update-skill-topology-test.sh
bash tests/update-copy-distributed-topology-test.sh
git diff --check
git status -sb
git commit -m "revert: restore pre-mirror skill layout"
```
