---
status: accepted
---

# Skills and plugins reduction and author taxonomy

This ADR synthesizes the closed wayfinder map (#23) and its three decision tickets — #24 (grouping mechanism), #25 (prune audit), #26 (author taxonomy) — into one plan-and-advice document. It records decisions only. **Executing the prunes, author-metadata registry, and `INDEX.md` generation is a separate follow-up effort and out of scope here.** ADR-0002's manifest-owned topology stays the governing distribution model; this ADR adds an orthogonal author axis and a cut-list on top of it.

## Grouping: flat skills, metadata + index — not folders (#24)

Skills stay in a flat `skills/` layout (`<root>/<skill>/SKILL.md`). Real per-author subfolders are rejected: Claude Code, Codex, and the topology `repo-owned.sh` adapter all discover skills flat and explicitly skip nested paths, so author subfolders would be undiscovered or clobbered. Grouping is therefore **metadata + a generated index**: a per-skill `author` value plus an `INDEX.md` grouped by author. A symlink farm was considered and rejected as heavier for no discovery benefit.

## Author taxonomy (#26)

Author is a **separate axis from distribution source**. `repo-claude` / `repo-codex` remain *distribution* sources; a skill is described as e.g. `source: repo-claude, author: steipete`. This dissolves the "marcus vs repo-claude" tension.

- **Buckets (short lowercase handles):** `marcus`, `steipete`, `matt`, `anthropic`, `khazix`. Plugin-only sources (topology sources not present in `skills/`) label by upstream handle: `tw93` (waza), `thedotmack` (claude-mem), `nicobailon` (visual-explainer), `openai` (openai-codex).
- **Assignment rule:** true **upstream author**, per skill — not the topology source. Where a source mixes authors, tie-break by the **git-add author** (`git log --diff-filter=A` on the skill's `SKILL.md`).
- **Storage:** an **explicit per-skill registry** — every skill states its `author`, with no source-level defaulting or inheritance. `INDEX.md` is generated from that registry; `skills/` stays flat.

Evidence: `git log --diff-filter=A` on each repo-owned `SKILL.md` gives a **19 steipete / 2 marcus** split; only `repo-claude` carried verifiable per-skill git history. Synced-set skills (matt/anthropic/khazix, gitignored copies with no local history) are attributed wholesale to their upstream owner — re-attributing a third-party skill nested inside a synced set is a future refinement, not blocking.

### Registry (86 skills, as audited)

- **`steipete` (19):** codex-first, create-cli, github-author-context, github-cache-hygiene, github-deep-review, github-project-triage, mac-maintenance, markdown-converter, nano-banana-pro, native-app-performance, obsidian, openai-image-gen, peekaboo, release-mac-app, reminders, remote-mac, skill-cleaner, ssh-doctor, video-transcript-downloader
- **`marcus` (2):** review-claudemd, validate-skills
- **`matt` (40):** ask-matt, batch-grill-me, claude-handoff, codebase-design, design-an-interface, diagnosing-bugs, domain-modeling, edit-article, git-guardrails-claude-code, grill-me, grill-with-docs, grilling, handoff, implement, improve-codebase-architecture, loop-me, migrate-to-shoehorn, obsidian-vault, prototype, qa, request-refactor-plan, research, resolving-merge-conflicts, scaffold-exercises, setup-matt-pocock-skills, setup-pre-commit, setup-ts-deep-modules, tdd, teach, to-questionnaire, to-spec, to-tickets, triage, ubiquitous-language, wayfinder, wizard, writing-beats, writing-fragments, writing-great-skills, writing-shape
- **`anthropic` (17):** algorithmic-art, brand-guidelines, canvas-design, claude-api, doc-coauthoring, docx, frontend-design, internal-comms, mcp-builder, pdf, pptx, skill-creator, slack-gif-creator, theme-factory, web-artifacts-builder, webapp-testing, xlsx
- **`khazix` (5):** aihot, hv-analysis, khazix-writer, neat-freak, storage-analyzer
- **`marcus` — staging (3):** onecli-gateway, onecli-run, onecli-run-workspace — pending #18 (`onecli-run-workspace` also flagged for prune below).

Total 19 + 2 + 40 + 17 + 5 + 3 = 86.

## Prune cut-list (#25) — advice for human approval

Two structural constraints gate any prune:

- **Synced sets aren't hand-picked.** matt / anthropic / khazix skills arrive as whole upstream sets; a durable cut needs a **topology-level exclude** (or a post-sync delete the next sync would undo), not a `git rm`.
- **Installed plugins are user-global**, not repo-scoped — cutting one affects every project, so those are personal-config calls, listed separately.

### A. Duplicates / overlaps

- **Grill family (4 → keep 1–2).** `grilling` is canonical; `grill-me`, `batch-grill-me`, `grill-with-docs` are older matt variants it subsumes. Keep `grilling`; keep `grill-with-docs` only for its ADR/glossary-emitting variant; cut `grill-me` + `batch-grill-me`.
- **Handoff pair.** `handoff` (writes a doc) vs `claude-handoff` (spawns a background agent) — same intent, keep one.
- **Obsidian pair.** repo-owned `obsidian` vs matt `obsidian-vault` — keep the owned (terser) one; cut `obsidian-vault`.
- **DDD pair.** `domain-modeling` largely covers `ubiquitous-language` — minor; keep `domain-modeling`.

### B. Unused / low-value / scaffolding

- **`onecli-run-workspace` — cut now.** No `SKILL.md`; only an `iteration-1/` skill-creator eval scaffold. Independent of #18.
- **`setup-matt-pocock-skills` — spent.** One-time repo bootstrap; issue tracker, triage labels, and domain docs already in place.
- **TS-only matt skills, irrelevant to this shell/bash repo:** `setup-ts-deep-modules`, `setup-pre-commit`, `migrate-to-shoehorn`, `scaffold-exercises`.
- **Meta / workspace scaffolds:** `ask-matt`, `loop-me`, `teach` — low marginal value.
- Note: `onecli-gateway` / `onecli-run` are **not** prunes — staged entrypoints pending #18.

### C. Redundant with an installed plugin

- **`frontend-design` + `skill-creator` provisioned to Claude twice** — as official plugins (`frontend-design@claude-plugins-official`, `skill-creator@claude-plugins-official`, Claude-only) and as anthropic-source synced copies (which exist to reach Codex). Fix: set those two `anthropic-skills` overrides to `["codex"]` — Codex keeps them, Claude drops the duplicate and uses the plugin.
- **Cross-source workflow overlap (review, don't auto-cut):** the **waza** plugin's think / write / check / hunt / research overlap matt's `grilling` / `writing-*` / `github-deep-review` / `diagnosing-bugs` / `research`. Decide whether both stacks stay.

### Installed-plugin candidates (user-global — personal-config call)

- `typescript-lsp@claude-plugins-official` — TS LSP; this repo is shell/bash.
- `frontend-design` / `skill-creator@claude-plugins-official` — keep plugin **or** synced copy, not both (see C).
- `claude-code-setup@claude-plugins-official` — one-time setup, likely spent.
- `superpowers@claude-plugins-official` — large meta-bundle; heavy overlap; review its context cost.

### Net if the high-confidence cuts land

`onecli-run-workspace`, `grill-me`, `batch-grill-me`, `obsidian-vault`, `setup-matt-pocock-skills`, plus the 2 Claude-side dedupes (`frontend-design`, `skill-creator`) → ~7 fewer skills, before the TS/meta and plugin decisions.

## Matt delivery: superseded state

The map assumed "copy matt skills to claude + codex" was already satisfied (`matt-skills` defaulting to both surfaces, 40 copies present in `skills/`). **That is no longer the topology.** Matt delivery was split (commit `0651785`): `matt-skills` is now **Codex-only npx** delivery, and a new **`mattpocock-skills` Claude plugin** source delivers the same skills to Claude via the plugin marketplace. Consequences the execution must account for:

- The 40 matt skills no longer appear as `skills/` copies on the Claude side (`skills/` is now 46, not 86). Their **author attribution is unchanged** (`matt`), but the `INDEX.md` generator must decide whether to enumerate plugin-delivered skills or only on-disk `skills/`.
- Any matt-skill prune (e.g. `grill-me`, `batch-grill-me`, `obsidian-vault`) is now a **topology-level exclude on the Codex npx source and/or the Claude plugin**, not a copy deletion.

## Consequences (execution, out of scope here)

- `author` and `source` diverge for exactly the 21 repo-owned skills (19 `steipete` + 2 `marcus`) under `repo-claude`; every other skill's author matches its set.
- The registry and `INDEX.md` generator are new artifacts; `skills/` stays flat (no moves).
- Synced-set prunes require topology-level excludes; installed-plugin cuts are personal, per-machine config, not repo state.
- Advice only: no skill deletions, `skill-topology.json` edits, or `INDEX.md` generation are performed by this ADR.
