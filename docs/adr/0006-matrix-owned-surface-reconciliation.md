---
status: accepted
---

# Matrix-owned surface reconciliation

The skills matrix is the sole selector for plain copies on the Claude and Codex surfaces. The offline `sync-skill-surfaces.sh` command reads the matrix directly, resolves each selected skill by name from tracked repository content, and reconciles both surfaces without reading the topology manifest or adapter registry. Repo-owned `skills/` content wins over foreign staging; otherwise exactly one `other-skills/<owner>/` candidate must resolve the name. The matrix `Source` column is informational.

All surface copies use one `skill-matrix` marker owner. The first reconciliation adopts copies carrying a known pre-cutover agent-scripts owner, restamping selected copies and cleaning unselected ones; unknown owners remain foreign. Reconciliation installs missing selected copies, refreshes changed selected copies, removes owned unselected copies, adopts an unmarked directory when it carries a pre-cutover marker source, is empty, or already matches the selected skill's upstream `SKILL.md`, and preserves every other unmarked directory with a report. Unresolvable or ambiguous rows are collected while resolvable changes still apply, then the command exits non-zero without removing a still-selected existing copy. Check mode, content-hash drift detection, the shared lock, and refusal of symlinked surface roots or entries remain in force.

Acquire remains manifest-driven and selection-blind. Its adapters stage foreign inventories or reconcile native plugins; they no longer copy to skill surfaces. The topology manifest retains only source ids, classifications, and default destinations. Generated overrides, the matrix override module, Claude-root migration, and the repo-owned distribute adapter are removed. The routine updater runs acquire, regenerates the matrix while preserving existing selections and appending new rows as unselected, then distributes.

This supersedes ADR-0004's generated-override mechanism and ADR-0005's clauses assigning matrix parsing, override persistence, report regeneration, and surface copies to the shared topology engine. ADR-0001's one-root-per-CLI invariant and ADR-0002's manifest-owned acquire policy remain in force.
