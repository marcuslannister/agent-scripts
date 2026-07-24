---
status: accepted
---

# Matrix-selected skill copies

Each CLI still reads exactly one skills root: Claude Code reads `~/.claude/skills`, and Codex reads `~/.agents/skills`. Both roots are reconciliation destinations populated with independently selected, marker-owned per-skill copies; neither root is a live link to the tracked authoring tree.

This supersedes only ADR-0001's clause that Claude Code reads repo `skills/` through a `~/.claude/skills` symlink. ADR-0001's one-root-per-CLI principle remains in force. ADR-0002's manifest-owned topology also remains in force, with the skills matrix now owning copy selection.

The matrix `Type` column is the policy discriminator for current and future sources:

- `Type: skill` rows are editable selection inputs. Their Claude and Codex `Y`/`N` cells independently determine which reconciled copies exist, and reconciliation generates the corresponding marked manifest overrides.
- `Type: plugin` rows are report-only. Plugin delivery stays under native plugin policy; editing their destination cells is rejected rather than silently ignored.

Consequences:

- Source identity does not decide editability; delivery type does.
- Repo-owned and staged foreign skills use the same selection rule.
- `scripts/update-skill-topology.sh` is the routine seam for validating matrix edits, reconciling both roots, and regenerating the matrix report.
- Managed-copy markers protect unrelated entries and make drift and cleanup verifiable.
