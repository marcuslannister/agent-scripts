# Agent Scripts

Shared agent instructions, skills, and small portable helpers for Peter's local workspaces.

This repo is the canonical place for:
- `AGENTS.MD`: shared hard rules for Codex/Claude-style agents
- `skills/`: reusable workflow skills, including repo-owned skills exposed by symlink
- `scripts/`: dependency-light helpers used across projects
- `hooks/`: local guardrails such as skill validation

## Skills

Skills are the main routing layer. Each `skills/<name>/SKILL.md` has YAML front matter:

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

Global discovery usually points here:
- `~/.codex/skills -> ~/Projects/agent-scripts/skills`
- `~/.claude/skills -> ~/Projects/agent-scripts/skills`

Shared personal skills live as real folders in `skills/`. Public OpenClaw shared skills live in `../agent-skills` and are exposed here with tracked relative symlinks. Repo-owned skills stay canonical in their repo and are exposed here the same way, for example:

```text
skills/autoreview -> ../../agent-skills/skills/autoreview
skills/discrawl -> ../../discrawl/.agents/skills/discrawl
```

Current symlinked repo-owned skills include `birdclaw`, `discrawl`, `gog`, `imsg`, `slacrawl`, `wacli`, and `wacrawl`.

## Agent Instructions

Shared hard rules live in `AGENTS.MD`.

Global setup:
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
- Top-level updater: runs `update-agents.sh`, `update-cc-plugins.sh`, `update-codex-plugins.sh`, `update-skills.sh`, `update-visual-explainer.sh`, then `update-khazix-skills.sh`.
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`scripts/update-agents.sh`
- Updates the agent CLIs: `claude update` (native) and `npm install -g @openai/codex`.
- Tries both even if one fails; prints version before/after each.

`scripts/update-cc-plugins.sh`
- Updates all Claude Code marketplaces and installed plugins.

`scripts/update-codex-plugins.sh`
- Refreshes configured Codex plugin marketplace snapshots with `codex plugin marketplace upgrade`.

`scripts/update-skills.sh`
- Updates skills.sh-managed agent skills; bootstraps Waza (`tw93/Waza`) if missing, then `npx skills update --global`.

`scripts/update-visual-explainer.sh`
- Clones/pulls `nicobailon/visual-explainer` under `~/Projects`, links the skill into `~/.codex/skills` with a relative symlink (`../../visual-explainer/plugins/visual-explainer`), and copies its prompt templates into `~/.codex/prompts`.

`scripts/update-khazix-skills.sh`
- Clones/pulls `KKKKhazix/khazix-skills` under `~/Projects` and links its `neat-freak` skill into `skills/` with a tracked relative symlink (`../../khazix-skills/neat-freak`).

`scripts/committer`
- Stages exactly the listed files.
- Enforces a non-empty commit message.
- Runs skill validation before committing.

`scripts/validate-skills`
- Checks every `skills/*/SKILL.md`.
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
