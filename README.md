# Agent Scripts

Shared agent instructions, skills, and small portable helpers for Peter's local workspaces.

This repo is the canonical place for:
- `AGENTS.MD`: shared hard rules for Codex/Claude-style agents
- `skill-topology.json`: versioned desired distribution for registered skill sources
- `skills/`: repo-owned Claude-authored skills plus untracked third-party copies
- `codex-skills/`: repo-owned Codex-only authoring source
- `scripts/`: dependency-light helpers used across projects
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
- Validate after edits: `scripts/validate-skills`.
- Quote `description` in front matter.

Global discovery — one skills root per CLI:
- Claude Code: `~/.claude/skills -> ~/Projects/agent-scripts/skills`
- Codex: `~/.agents/skills` only; default `scripts/update-skill-topology.sh` reconciliation installs repo-owned skills approved by `skill-topology.json`. Claude-authored skills default to Claude, 21 named skills explicitly reach both surfaces, `codex-first` remains Claude-only, and `maintainer-orchestrator` is authored under `codex-skills/` for Codex only.
- The old `~/.codex/skills` root is legacy. `scripts/update-repo-skills.sh` still owns its migration/backup recovery until root hygiene moves into the topology module; it is not part of routine updates.
- Evidence note: `C:\Users\<user>\.codex\skills-migrated-20260707-091501` was the local backup that shaped the migration tests (legacy skill dirs plus plain pointer files). It is documentation evidence only; scripts and tests must synthesize their own fixtures instead of depending on that path.
- Recovery from migrated backups: `docs/codex-skill-backup-recovery.md`.

Shared personal skills live as real folders in `skills/`. Third-party skills arrive as untracked rsync copies behind marker-delimited ignore blocks (tracked `.gitignore` or repo-local `.git/info/exclude`; see the `scripts/update-*-skills.sh` updaters); `skills/` contains no symlinks.

## Agent Instructions

Shared hard rules live in `AGENTS.MD`.

Global setup (Claude Code reads `CLAUDE.md` only, so it links to the shared `AGENTS.MD`):
- `~/.codex/AGENTS.md -> ~/Projects/agent-scripts/AGENTS.MD`
- `~/.claude/CLAUDE.md -> ~/Projects/agent-scripts/AGENTS.MD`
- `~/.claude/AGENTS.md -> ~/Projects/agent-scripts/AGENTS.MD`

Downstream repos should use a pointer-style `AGENTS.MD`:

```text
READ ~/Projects/agent-scripts/AGENTS.MD BEFORE ANYTHING (skip if missing).
```

Repo-specific rules go below that pointer. Do not copy the shared blocks into downstream repos.

## Helpers

`scripts/update-all.sh`
- Top-level updater: runs `update-agents.sh`, `update-cli-skills.sh`, `update-visual-explainer.sh`, `update-khazix-skills.sh`, `update-anthropic-skills.sh`, then `update-mattpocock-skills.sh`; generic and direct plugin updates stay outside routine execution.
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`scripts/verify.sh`
- Single local/CI verifier: skill validation, Bash syntax, updater/copy regressions, maintainer policy, browser helper tests/build, and video-downloader smoke checks.
- Missing tools or installed dependencies fail early with setup guidance.

`scripts/update-skill-topology.sh`
- Default mode discovers repo-owned, Matt, Anthropic, neat-freak, visual-explainer, Waza, and claude-mem inventories, validates the complete manifest plan before distribution writes, reconciles approved copies/plugins, performs owner-scoped cleanup, and verifies every managed destination. Unmarked and other-owner entries remain untouched.
- Add `--check` for a non-mutating preview or `--json` for one stable JSON document. Exit codes: `0` reconciled/check-clean, `1` drift/adapter/verification failure, `2` invalid usage or manifest, `3` user decision required, `130` interrupted.
- Waza and claude-mem use manifest-scoped native Claude/Codex adapters. Unknown installed third-party plugins return decision-required before mutation; Claude official and Codex system plugins are ignored. Claude-mem still requires runnable Bun, uv, and uvx and preserves the shared `~/.claude-mem` worker/database contract.
- Matt skills default to both surfaces, with `code-review` Codex-only because Claude supplies that built-in. Unknown npx lock sources return decision-required; `find-skills` is retired and its known lock/copy state is removed during reconciliation.
- Staged migration: legacy per-source commands below remain callable until the final routine-updater cutover. Generic plugin mutation delegates to manifest topology, generic npx mutation is inert, and direct Waza/claude-mem commands are no longer routine steps.

`scripts/update-agents.sh`
- Updates the agent CLIs: `claude update` (native) and `npm install -g @openai/codex`.
- Tries both even if one fails; prints version before/after each.

`scripts/update-cc-plugins.sh`
- Compatibility entrypoint that delegates to `update-skill-topology.sh`; bulk installed-plugin mutation is no longer available outside manifest policy.

`scripts/update-cli-skills.sh`
- Staged inert public-CLI compatibility entrypoint retained only until issue #18's final cutover. Generic npx updates and `find-skills` bootstrap are retired; use `update-skill-topology.sh`.

`scripts/update-waza.sh`
- Legacy direct entrypoint retained during staged migration. `update-skill-topology.sh` owns routine Waza policy and native installation on both surfaces.

`scripts/update-mattpocock-skills.sh`
- Reconciles Matt Pocock's complete upstream skill set into `~/.agents/skills` for Codex: updates changed skills, installs additions, and removes canonical directories deleted or renamed upstream. Then rsyncs the current set into `skills/` as untracked copies for Claude Code (deny-list: `code-review`, which would collide with the built-in), removing stale copies and regenerating a repo-local `# matt-skills` block in `.git/info/exclude` so upstream churn does not dirty tracked files.

`scripts/update-visual-explainer.sh`
- Clones/pulls `nicobailon/visual-explainer` under `~/Projects`, then rsyncs the plugin dir to `~/.agents/skills/visual-explainer` (Codex's user skill root) as a copy — never a symlink. Claude Code gets it as a marketplace plugin instead.

`scripts/update-khazix-skills.sh`
- Clones/pulls `KKKKhazix/khazix-skills` under `~/Projects` and rsyncs its `neat-freak` skill into `skills/` as an untracked copy behind a `# khazix-skills` block in `.gitignore`.

`scripts/update-anthropic-skills.sh`
- Clones/pulls `anthropics/skills` into `~/Projects/anthropic-skills`, rsyncs `docx`, `xlsx`, `pdf`, and `pptx` into `skills/` as untracked copies behind an `# anthropic-skills` block in `.gitignore`, copies those same document skills into `~/.agents/skills` for Codex, and copies `frontend-design` + `skill-creator` into `~/.agents/skills` only: Claude Code ships both via plugins and does not read `~/.agents/skills`, so Codex gets them without duplicating the plugins.

`scripts/update-claude-mem.sh`
- Legacy direct entrypoint retained during staged migration. `update-skill-topology.sh` owns routine claude-mem policy, dependency checks, native installation on both surfaces, and final verification without touching the shared `~/.claude-mem` worker/database.

`scripts/committer`
- Stages exactly the listed files.
- Enforces a non-empty commit message.
- Runs skill validation before committing.

`scripts/sync-skills`
- Builds the per-machine skill mirror: Codex whole-root links, Claude flat per-skill links, shared `AGENTS.MD` pointers.
- Idempotent; prints changes only, prunes broken/stale managed links, never clobbers real files.

`scripts/validate-skills`
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
- Build optional binary with `bun build scripts/browser-tools.ts --compile --target bun --outfile bin/browser-tools`.

## Syncing

Treat this repo as canonical for shared agent rules and portable helper scripts.

When syncing downstream repos:
- Pull latest here first.
- Ensure each target repo starts with the pointer-style `AGENTS.MD`.
- Preserve repo-local rules below the pointer.
- Copy helper changes both directions only when the helper is meant to stay byte-identical.
- Keep scripts dependency-free and portable; no repo-specific imports or path aliases.

For submodules, repeat the pointer check inside each subrepo, push those changes, then bump submodule SHAs in the parent repo.
