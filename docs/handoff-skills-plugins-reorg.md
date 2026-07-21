# Handoff — skills-plugins-reorg (execution)

_Session: ADR-0003 execution kickoff · 2026-07-21 · repo `marcuslannister/agent-scripts` (public) · branch `main` clean + pushed_

Supersedes the wayfinder-phase handoff (map now closed; see #23 + ADR-0003).

## What the next session is for

Two concrete open loops remain. Neither is started.

1. **Finish the `onecli-run-workspace` prune.** The maintainer chose to delete it, but the `rm -rf` was blocked by the permission gate, so `skills/onecli-run-workspace/` is still on disk (untracked). After the maintainer runs `! rm -rf skills/onecli-run-workspace`: drop its entry from `skill-authors.json` (86 → 85), change the `length == 86` assertion in `tests/skill-index-test.sh` to `85`, regenerate the index (`scripts/generate-skill-index.sh`), run the test, commit.
2. **Unblock + apply the deferred runtime reconcile.** The anthropic de-dupe (commit `d5c91c0`) is committed at the manifest layer but NOT applied at runtime. A full reconcile is blocked (see gotchas). Investigating the `visual-explainer: invalid-plugin-settings` failure and the unsynced Codex surface, then running a real reconcile, applies both the anthropic Claude removal and the Codex resync.

Optional / maintainer's call: installed-plugin cuts (`typescript-lsp`, `superpowers`, `claude-code-setup@claude-plugins-official`) — user-global config, not repo state.

## State — read these, don't re-derive

- **Plan of record:** `docs/adr/0003-skills-plugins-reduction-and-author-taxonomy.md` — author taxonomy, prune cut-list, and an "Execution outcomes (2026-07-21)" section recording every decision below. Read this first.
- **Closed map:** issue #23 <https://github.com/marcuslannister/agent-scripts/issues/23> (decisions #24/#25/#26 closed inside it).
- **This session's commits (all pushed to `main`):**
  - `0651785` split matt into codex-npx + claude-plugin sources (+ fixed 2 topology tests)
  - `f767f2d` ADR-0003 synthesis
  - `d5c91c0` anthropic `frontend-design`/`skill-creator` → Codex-only (manifest only)
  - `ce8a90d` author registry + generated `INDEX.md` + generator + test
  - `fe724c1` ADR-0003 execution outcomes
- **New artifacts:** `skill-authors.json` (registry, 86), `scripts/generate-skill-index.sh` (`--check` gates freshness + fails on unattributed on-disk skill), `INDEX.md`, `tests/skill-index-test.sh`.

## Decisions already made (do not relitigate)

- **matt-skill prunes: dropped.** matt now ships as one Claude plugin (`mattpocock-skills`, all 40 skills wholesale) + npx-all to Codex. No per-skill deletion on Claude → accepted all-or-nothing. `grill-me`, `batch-grill-me`, `obsidian-vault`, `setup-matt-pocock-skills` stay.
- **Runtime apply: deferred** (manifest is source of truth).
- **`onecli-run-workspace`: delete** (pending, open loop 1). `onecli-gateway` + `onecli-run` are kept (staging, pending #18).

## Gotchas (not captured elsewhere)

- **Topology reconcile is env-blocked on this machine.** `./scripts/update-skill-topology.sh --check` returns `failed (48 changes)`: hard error `cannot verify visual-explainer/visual-explainer on claude: invalid-plugin-settings` (this HALTS reconcile), the entire Codex surface shows `installed:missing` (unsynced here), and `waza` is `disabled`. None of this is from the reorg — pre-existing. Fix visual-explainer's plugin settings before expecting any reconcile to apply.
- **No scoped reconcile.** The tool runs all sources; one source's inspection failure blocks the whole apply. That's why the anthropic change can't be applied in isolation right now.
- **Override `[]` excludes a skill**, but only for per-skill sources (copy/npx). Plugin sources are all-or-nothing.
- **Commit helper:** `./scripts/committer "<msg>" <file>...` (validates 46 skills, then commits). This repo is authorized for commit+push without asking.
- **zsh test-runner traps:** `noclobber` breaks `> file` reuse — use `>|` and a fresh `mktemp` per test. Topology tests are slow; `topology-no-node-test.sh` re-runs a full sub-suite and can exceed a 2-minute timeout — run it (and `update-skill-topology-test.sh`) individually with a longer timeout.
- **Green baseline:** all 9 topology tests + `tests/skill-index-test.sh` pass.

## Suggested skills

- `/health` (waza) — for the `visual-explainer: invalid-plugin-settings` / config-drift blocker (open loop 2). This is agent/plugin config rot, its wheelhouse.
- `mattpocock-skills:diagnosing-bugs` or `/hunt` (waza) — if the reconcile failure needs a tight reproduce-then-fix loop rather than a config audit.
- `/check` (waza) or `mattpocock-skills:code-review` — before committing the registry/test edits in open loop 1.
