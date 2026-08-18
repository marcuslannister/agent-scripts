# Agent Scripts

Shared agent instructions, skills, and small portable helpers for Peter's local workspaces.

This repo is the canonical place for:
- `AGENTS.MD`: shared hard rules for Codex/Claude-style agents
- `agent-tooling/`: code-agent and skill update machinery — matrix generator, staging acquire, surface distribute, verify/validate gates, `skill-authors.json`, `sources.json` (the one tracked list of skill-bearing sources), `skills-matrix.md`
- repository root: upstream-complete overlay of `steipete/agent-scripts:main`; every recorded upstream path remains present while local additions and modifications coexist
- `skills/`: exact tracked mirror of `steipete/agent-scripts:main`
- `other-skills/`: owner-grouped tracked holding area for foreign skills; each source dir carries `.source.json` provenance
- `codex-skills/`: repo-owned Codex-only authoring source
- `scripts/`: dependency-light personal helpers used across projects
- `hooks/`: local guardrails such as skill validation

## Skills

Skills are the main routing layer. Each `skills/<name>/SKILL.md` or `codex-skills/<name>/SKILL.md` has YAML front matter:

```yaml
---
name: skill-name
description: "Short generic trigger phrase."
---
```

Rules:
- Keep descriptions short and generic; optimize for routing, not documentation.
- Keep skill bodies terse and operational.
- Prefer helper scripts under `skills/<name>/scripts/` when a workflow has repeatable commands.
- Validate after edits: `agent-tooling/validate-skills`.
- Quote `description` in front matter.

Global discovery — one skills root per CLI:
- Claude Code: `~/.claude/skills` only; `agent-tooling/update-skill-topology.sh` acquires upstream inventories into tracked staging; `agent-tooling/sync-skill-surfaces.sh` distributes matrix-selected, marker-owned copies offline. Native plugins are user-managed per-machine state refreshed best-effort by `agent-tooling/update-plugins.sh` (ADR-0009).
- Codex: `~/.agents/skills` only; the same matrix selects every `Type: skill` row independently for Claude and Codex. `Type: plugin` rows remain report-only.
- The old `~/.codex/skills` root is legacy. Distribute migrates every non-system entry into collision-safe timestamped backups and verifies that only Codex's `.system` entry may remain.
- Evidence note: `C:\Users\<user>\.codex\skills-migrated-20260707-091501` was the local backup that shaped the migration tests (legacy skill dirs plus plain pointer files). It is documentation evidence only; scripts and tests must synthesize their own fixtures instead of depending on that path.
- Recovery from migrated backups: `docs/codex-skill-backup-recovery.md`. Upstream mirror rollback: `docs/upstream-skills-mirror-rollback.md`.

Tracked `skills/` content mirrors `steipete/agent-scripts:main` exactly, including upstream-owned symlinks. Tracked mirror names win source collisions. Source-only and npx-only inventories stage under tracked `other-skills/<owner>/` (no per-skill copy markers; provenance in `.source.json`), never directly in an agent surface.

## Agent Instructions

Shared hard rules live in `AGENTS.MD`.

Run `agent-tooling/setup-agent-instructions.sh` explicitly once per machine. It creates missing shared pointers, preserves real files and foreign symlinks, and is never called by routine skill updates. Claude Code reads `CLAUDE.md`, so setup creates:
- `~/.codex/AGENTS.md -> ~/Projects/agent-scripts/AGENTS.MD`
- `~/.claude/CLAUDE.md -> ~/Projects/agent-scripts/AGENTS.MD`
- `~/.claude/AGENTS.md -> ~/Projects/agent-scripts/AGENTS.MD`

Downstream repos should use a pointer-style `AGENTS.MD`:

```text
READ ~/Projects/agent-scripts/AGENTS.MD BEFORE ANYTHING (skip if missing).
```

Repo-specific rules go below that pointer. Do not copy the shared blocks into downstream repos.

## Helpers

`agent-tooling/sync-upstream-overlay.sh`
- Public upstream sync command. Requires a clean worktree, fetches and merges `steipete/agent-scripts:main`, restores upstream paths deleted by local history, and records the verified source commit without overwriting local additions or committed modifications.
- `--check` is offline. It verifies that the recorded commit is merged into `HEAD` and that every path in that commit remains present.

`agent-tooling/update-all.sh` — the one command on the main machine
- Five ordered steps: `update-agents.sh`, `update-plugins.sh`, `update-skill-topology.sh` (acquire), `generate-skills-matrix.sh`, then `sync-skill-surfaces.sh` (distribute).
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.
- Ships by default: requires a clean worktree, pulls first, validates the update, adds an Unreleased changelog entry, commits the refresh, pushes, pulls with fast-forward only, and verifies the final worktree state. `--no-ship` runs the update steps only.

`agent-tooling/update-local.sh` — the one command on every other machine
- Fast-forward pulls the repo, then three ordered steps: `update-agents.sh`, `update-plugins.sh`, then `sync-skill-surfaces.sh` (distribute). No staging acquire and no matrix refresh; this machine distributes already-committed staging.
- Runs on macOS and on Windows under Git Bash. Windows needs `jq` and `rg` on PATH once.
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`agent-tooling/update-plugins.sh`
- Best-effort native plugin refresh on every machine: runs the native `claude`/`codex` update commands for each plugin source in `sources.json`, skips marketplaces marked `"codexUpgrade": "manual"` (ADR-0007), reports each failure in one line, and never fails the run.
- It never installs a plugin and never repairs a registry. First-time installs are native commands you run once; a desynced Codex registry is `agent-tooling/repair-codex-registry.sh`.

`agent-tooling/repair-claude-mem-marker.sh`
- Explicit per-machine repair for Codex claude-mem installs that lack the runtime `.install-version` marker. It repairs by default; `--check` reports drift without writing. It changes only that marker to the version in each installed package and is not part of routine updates (ADR-0007).

`agent-tooling/verify.sh`
- Single local/CI verifier: upstream-overlay completeness, skill validation, Bash syntax, topology cutover policy, updater/copy regressions, Bash maintainer policy, browser helper tests/runtime smoke, and video-downloader smoke checks; the maintainer policy path does not require Ruby.
- Missing tools or installed dependencies fail early with setup guidance.

`agent-tooling/update-skill-topology.sh` / `agent-tooling/sync-skill-surfaces.sh`
- Both commands are Bash and neither invokes nor requires Node. Browser-helper verification keeps its unrelated Node requirement.
- Acquire (`update-skill-topology.sh`) refreshes one cached shallow clone per source under `~/.cache/agent-scripts/source-clones/`, mirrors complete foreign inventories into tracked `other-skills/` staging with `.source.json` provenance, and removes staged skills that left upstream. It is selection-blind, never manages agent surfaces, and runs no native plugin commands (ADR-0009). `--check` previews staging drift and writes nothing at all, including under `HOME`.
- Distribute (`sync-skill-surfaces.sh`) is fully offline and matrix-owned. It resolves selected names from tracked repo and staging content, reconciles both surfaces under one marker owner, adopts known pre-cutover agent-scripts owners, removes owned unselected copies, preserves and reports foreign entries, and reads only the matrix and tracked content.
- Both print their result plus per-skill actions, keep diagnostics on standard error, and support `--check` for a non-mutating preview or `--json` for one JSON document. Acquire exit codes are `0` reconciled/check-clean, `1` drift or staging failure, `2` invalid usage or sources list, `3` decision required (unexpected skills-lock entries), and `130` interrupted. Distribute uses `0` for reconciled/check-clean, `1` for drift or reconciliation failure, `2` for invalid usage or matrix, and `130` for interruption.
- Plugin sources (OpenAI Codex, Waza, claude-mem, mattpocock-skills, visual-explainer) carry only a `plugin` block in `sources.json`, read by `update-plugins.sh`, `repair-codex-registry.sh`, and matrix reporting. `Type: plugin` matrix rows stay report-only. Tooling never substitutes a surface copy for a broken plugin. Claude-mem still requires runnable Bun, uv, and uvx and preserves the shared `~/.claude-mem` worker/database contract.
- The matrix currently selects most Matt skills for both surfaces, with `code-review` Codex-only because Claude supplies that built-in. Unknown npx lock sources return decision-required; known legacy npx lock entries also require an explicit decision and remain byte-identical.
- Exit `3` from acquire means a skills-lock entry needs an explicit decision; the lock is never mutated. Inspect `--json` decisions, act deliberately, then rerun.

`agent-tooling/update-agents.sh`
- Updates the agent CLIs: `claude update` (native), `npm install -g @openai/codex`, `pi update` plus `pi update --extensions`, and Grok through its native installer; installs a missing Pi or Grok with the same native installer.
- Tries all installed CLIs even if one fails.

Removed public commands: `update-repo-skills.sh`, `update-cc-plugins.sh`, `update-cli-skills.sh`, `update-waza.sh`, `update-claude-mem.sh`, `update-mattpocock-skills.sh`, `update-visual-explainer.sh`, `update-khazix-skills.sh`, and `update-anthropic-skills.sh`. No aliases or shims. `scripts/sync-skills` is a retired stub kept only for upstream-path completeness (ADR-0008/0009).

Topology authoring:
- Run `agent-tooling/sync-upstream-overlay.sh` to merge the latest upstream root and restore every upstream path before local topology updates.
- Refresh tracked `skills/` from the upstream `steipete/agent-scripts:main` mirror; do not add fork-only content there. Mirrored skills default to Claude.
- Put repo-owned Codex-only skills under `codex-skills/`; they default to Codex.
- Select Claude/Codex destinations by editing `Y`/`N` on `Type: skill` rows in `agent-tooling/skills-matrix.md`; the sources list has no distribution overrides.
- Review newly appended skill rows and change `N/N` only when the skill should reach a surface. Selected rows that no longer resolve fail loudly; unselected rows do not block reconciliation. Plugin rows and their destination cells are report-only.
- For an external skill-bearing source, add exactly one `agent-tooling/sources.json` entry: `id`, `classification`, `repo`, plus `subroot`/`staging`/`discovery` for staged sources or a `plugin` block for plugin sources. Stage source-only and npx-only inventories under the matching `other-skills/<owner>/`; never write them directly into `skills/`. Never add another public updater.
- Preview upstream/staging drift with `agent-tooling/update-skill-topology.sh --check`; run it to acquire. Regenerate `agent-tooling/skills-matrix.md` to append new skills without changing selections, then preview surfaces offline with `agent-tooling/sync-skill-surfaces.sh --check`. Run `agent-tooling/verify.sh` before commit.

`agent-tooling/setup-agent-instructions.sh`
- Explicit one-machine setup for the three shared `AGENTS.MD`/`CLAUDE.md` pointers; not part of topology reconciliation or routine updates.
- Idempotent; preserves real user files and foreign symlinks.

`agent-tooling/validate-skills`
- Checks every repo-owned `skills/*/SKILL.md` and `codex-skills/*/SKILL.md`.
- Verifies YAML front matter plus required `name` and `description`.
- Enable as a local hook with `git config core.hooksPath hooks`.
- Requires Python 3 with PyYAML (`pip install pyyaml`; add `--break-system-packages` on an externally-managed Python).

`scripts/docs-list.ts`
- Walks `docs/`.
- Enforces `summary` and `read_when` front matter.
- Prints onboarding summaries for repos that wire it in.

`scripts/browser-tools.ts`
- Standalone Chrome DevTools helper.
- Common commands: `start --profile`, `nav <url>`, `eval '<js>'`, `screenshot`, `console`, `network`, `search --content "<query>"`, `content <url>`, `inspect`, `kill --all --force`.
- Requires Node.js 22.18 or newer; run with `node scripts/browser-tools.ts --help`.

## Syncing

Treat this repo as canonical for shared agent rules and portable helper scripts.

When syncing downstream repos:
- Pull latest here first.
- Ensure each target repo starts with the pointer-style `AGENTS.MD`.
- Preserve repo-local rules below the pointer.
- Copy helper changes both directions only when the helper is meant to stay byte-identical.
- Keep scripts dependency-free and portable; no repo-specific imports or path aliases.

For submodules, repeat the pointer check inside each subrepo, push those changes, then bump submodule SHAs in the parent repo.
