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

Global discovery — one skills root per CLI:
- Claude Code: `~/.claude/skills -> ~/Projects/agent-scripts/skills`
- Codex: `~/.agents/skills` only; `scripts/update-repo-skills.sh` (part of `update-all.sh`) syncs the tracked skills in `skills/` there as marked copies. The old `~/.codex/skills` symlink is gone — it made Codex load both roots and see duplicates of every synced skill. If legacy entries reappear under `~/.codex/skills`, the updater moves every non-`.system` entry into `~/.codex/skills-migrated-<timestamp>`, leaves the active Codex surface untouched, then verifies the old root has no non-system entries and every tracked repo skill is present as a marked copy under `~/.agents/skills`.
- Evidence note: `C:\Users\<user>\.codex\skills-migrated-20260707-091501` was the local backup that shaped the migration tests (legacy skill dirs plus plain pointer files). It is documentation evidence only; scripts and tests must synthesize their own fixtures instead of depending on that path.

Shared personal skills live as real folders in `skills/`. Third-party skills arrive as untracked rsync copies behind marker-delimited `.gitignore` blocks (see the `scripts/update-*-skills.sh` updaters); `skills/` contains no symlinks.

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
- Top-level updater: runs `update-agents.sh`, `update-cc-plugins.sh`, `update-cli-skills.sh`, `update-visual-explainer.sh`, `update-khazix-skills.sh`, `update-anthropic-skills.sh`, `update-claude-mem.sh`, `update-waza.sh`, `update-mattpocock-skills.sh`, then `update-repo-skills.sh`.
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`scripts/update-agents.sh`
- Updates the agent CLIs: `claude update` (native) and `npm install -g @openai/codex`.
- Tries both even if one fails; prints version before/after each.

`scripts/update-cc-plugins.sh`
- Updates all Claude Code marketplaces and installed plugins.

`scripts/update-cli-skills.sh`
- Removes legacy tw93/Waza skills-CLI installs (Waza is a marketplace plugin now), bootstraps `find-skills` (vercel-labs/skills) when missing, then runs `npx skills update --global`, refreshing every skills.sh-managed package, including Matt Pocock's canonical copies. Also rsyncs one-off npx skills both agents need (`find-skills`) into `skills/` as untracked copies behind a `# cli-skills` block in `.gitignore`.

`scripts/update-waza.sh`
- Installs/updates `tw93/Waza` for Claude Code and Codex via each CLI's plugin marketplace (marketplace `waza` on both sides). The umbrella `waza` plugin registers all eight skills namespaced as `/waza:think`, `/waza:check`, etc.; no entries in `skills/`.

`scripts/update-mattpocock-skills.sh`
- Installs/updates Matt Pocock's skills: bootstraps `mattpocock/skills` (`--agent codex`, canonical copies in `~/.agents/skills` for Codex) if missing, then rsyncs every Matt skill into `skills/` as untracked copies for Claude Code (deny-list: `code-review`, which would collide with the built-in) and regenerates a marker-delimited `# matt-skills` block in `.gitignore` so the copies never enter the repo. Runs after `update-cli-skills.sh`, which refreshes the canonical copies.

`scripts/update-visual-explainer.sh`
- Clones/pulls `nicobailon/visual-explainer` under `~/Projects`, then rsyncs the plugin dir to `~/.agents/skills/visual-explainer` (Codex's user skill root) as a copy — never a symlink. Claude Code gets it as a marketplace plugin instead.

`scripts/update-khazix-skills.sh`
- Clones/pulls `KKKKhazix/khazix-skills` under `~/Projects` and rsyncs its `neat-freak` skill into `skills/` as an untracked copy behind a `# khazix-skills` block in `.gitignore`.

`scripts/update-anthropic-skills.sh`
- Clones/pulls `anthropics/skills` into `~/Projects/anthropic-skills`, rsyncs `docx`, `xlsx`, `pdf`, and `pptx` into `skills/` as untracked copies behind an `# anthropic-skills` block in `.gitignore`, and copies `frontend-design` + `skill-creator` into `~/.agents/skills` (Codex-only): Claude Code ships both via plugins and does not read `~/.agents/skills`, so Codex gets them without duplicating the plugins.

`scripts/update-claude-mem.sh`
- Requires runnable Bun and Astral `uv` first because claude-mem hooks run through `bun-runner.js` and vector search uses `uvx`; checks Scoop, `~/.bun`, Homebrew, and PATH locations, then fails before install/update if either dependency is missing or broken. Installs/updates `thedotmack/claude-mem` for Claude Code (marketplace `thedotmack`) and Codex (marketplace `claude-mem-local`) via each CLI's plugin marketplace commands; no npx installer. Both tools share one claude-mem worker and database under `~/.claude-mem`.

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
