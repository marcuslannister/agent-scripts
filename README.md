# Agent Scripts

Shared agent instructions, skills, and small portable helpers for Peter's local workspaces.

This repo is the canonical place for:
- `AGENTS.MD`: shared hard rules for Codex/Claude-style agents
- `agent-tooling/`: code-agent and skill update machinery — matrix generator, distribution-topology reconciler, verify/validate gates, `skill-authors.json`, `skill-topology.json` (versioned desired distribution for registered skill sources), `skills-matrix.md`
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
- Claude Code: `~/.claude/skills` only; `agent-tooling/update-skill-topology.sh` acquires upstream inventories into tracked staging and reconciles native plugins; `agent-tooling/sync-skill-surfaces.sh` distributes matrix-selected, marker-owned copies offline.
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

`agent-tooling/update-all.sh`
- Top-level updater: four ordered steps — `update-agents.sh`, `update-skill-topology.sh` (acquire), `generate-skills-matrix.sh`, then `sync-skill-surfaces.sh` (distribute).
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`agent-tooling/verify.sh`
- Single local/CI verifier: skill validation, Bash syntax, topology cutover policy, updater/copy regressions, Bash maintainer policy, browser helper tests/runtime smoke, and video-downloader smoke checks; the maintainer policy path does not require Ruby.
- Missing tools or installed dependencies fail early with setup guidance.

`agent-tooling/update-skill-topology.sh` / `agent-tooling/sync-skill-surfaces.sh`
- Public commands and private topology core are Bash; topology reconciliation neither invokes nor requires Node. Browser-helper verification keeps its unrelated Node requirement.
- Acquire (`update-skill-topology.sh`) refreshes upstreams, mirrors complete foreign inventories into tracked `other-skills/` staging with `.source.json` provenance, and reconciles native plugins (including verified dual-plugin duplicate cleanup). It never reads or writes the matrix and never manages ordinary agent surfaces. `--check` previews only upstream/staging and native-plugin drift without writes.
- Distribute (`sync-skill-surfaces.sh`) is fully offline and matrix-owned. It resolves selected names from tracked repo and staging content, reconciles both surfaces under one marker owner, adopts known pre-cutover agent-scripts owners, removes owned unselected copies, preserves and reports foreign entries, and reads neither the topology manifest nor adapter registry.
- Acquire human mode streams discovery, planning, adapter, and verification progress before its result table; distribute prints its surface result and add/refresh/remove actions. Both keep diagnostics on standard error and support `--check` for a non-mutating preview or `--json` for one JSON document. Acquire exit codes are `0` reconciled/check-clean, `1` drift/adapter/verification failure, `2` invalid usage or manifest, `3` user decision required, and `130` interrupted. Distribute uses `0` for reconciled/check-clean, `1` for drift or reconciliation failure, `2` for invalid usage or matrix, and `130` for interruption.
- OpenAI Codex is Claude-only; Waza and claude-mem are dual-plugin skills with manifest-scoped native Claude/Codex adapters and explicit expected skill identities. Check mode compares installed versions with each configured marketplace snapshot, confirms every declared skill through each native plugin install, and reports pending/blocked/verified migration gates plus retained and eventual duplicate-copy removals without mutation. Reconciliation removes tracked, untracked, managed, or edited copies of only the verified skill after both native paths pass; partial native success retains both copies, and cleanup failure remains visible without fallback delivery. Human and JSON output separate native reconciliation, runtime verification, retained copies, gated removals, and blocking failures; repeated healthy reconciliation reports clean/idempotent state. Recovery stays plugin-managed and is limited to upstream repair, native rollback, or an explicit manifest decision. Unknown installed third-party plugins return decision-required before mutation; Claude official and Codex system plugins are ignored. Report-only plugin rows disappear on regeneration when their local cache is removed, and their destination cells remain informational. Claude-mem still requires runnable Bun, uv, and uvx and preserves the shared `~/.claude-mem` worker/database contract.
- The matrix currently selects most Matt skills for both surfaces, with `code-review` Codex-only because Claude supplies that built-in. Unknown npx lock sources return decision-required; known legacy npx lock entries also require an explicit decision and remain byte-identical.
- Exit `3` from acquire means no native-plugin or staging mutation occurred. Inspect `--check --json` decisions, make an explicit manifest or installed-state decision, then rerun; do not guess a fallback or delete unowned entries.

`agent-tooling/update-agents.sh`
- Updates the agent CLIs: `claude update` (native) and `npm install -g @openai/codex`.
- Tries both even if one fails; prints version before/after each.

Removed public commands: `update-repo-skills.sh`, `update-cc-plugins.sh`, `update-cli-skills.sh`, `update-waza.sh`, `update-claude-mem.sh`, `update-mattpocock-skills.sh`, `update-visual-explainer.sh`, `update-khazix-skills.sh`, and `update-anthropic-skills.sh`. No aliases or shims. Their mechanics now live only in `agent-tooling/distribution-topology/adapters/`.

Topology authoring:
- Refresh tracked `skills/` from the upstream `steipete/agent-scripts:main` mirror; do not add fork-only content there. Mirrored skills default to Claude.
- Put repo-owned Codex-only skills under `codex-skills/`; they default to Codex.
- Select Claude/Codex destinations by editing `Y`/`N` on `Type: skill` rows in `agent-tooling/skills-matrix.md`; the topology manifest has no distribution overrides.
- Review newly appended skill rows and change `N/N` only when the skill should reach a surface. Selected rows that no longer resolve fail loudly; unselected rows do not block reconciliation. Plugin rows and their destination cells are report-only.
- For an external skill-bearing source, add exactly one `agent-tooling/skill-topology.json` source and one private adapter registration with its matrix source identity. Stage source-only and npx-only inventories under the matching `other-skills/<owner>/`; never write them directly into `skills/`. Record source defaults and plugin policy in the manifest; never add another public updater.
- Preview upstream/staging drift with `agent-tooling/update-skill-topology.sh --check`; run it to acquire. Regenerate `agent-tooling/skills-matrix.md` to append new skills without changing selections, then preview surfaces offline with `agent-tooling/sync-skill-surfaces.sh --check`. Run `agent-tooling/verify.sh` before commit.

`scripts/committer`
- Stages exactly the listed files.
- Enforces a non-empty commit message.
- Runs skill validation before committing.

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
