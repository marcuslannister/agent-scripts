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
- Claude Code: `~/.claude/skills` only; `agent-tooling/sync-skill-surfaces.sh` (offline distribute) installs marker-owned per-skill copies selected by `agent-tooling/skills-matrix.md`; `agent-tooling/update-skill-topology.sh` still runs the full single-pass reconcile until the acquire-only split lands.
- Codex: `~/.agents/skills` only; the same matrix selects every `Type: skill` row independently for Claude and Codex. `Type: plugin` rows remain report-only.
- The old `~/.codex/skills` root is legacy. Distribute and the full topology command migrate every non-system entry into collision-safe timestamped backups and verify that only Codex's `.system` entry may remain.
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
- Top-level updater: exactly two ordered steps — `update-agents.sh`, then `update-skill-topology.sh` (full reconcile). Offline surface sync: `sync-skill-surfaces.sh`. Three-step acquire/distribute updater lands in the follow-up.
- No fail-fast; prints a `✓`/`✗` summary and exits non-zero if any step failed.

`agent-tooling/verify.sh`
- Single local/CI verifier: skill validation, Bash syntax, topology cutover policy, updater/copy regressions, Bash maintainer policy, browser helper tests/runtime smoke, and video-downloader smoke checks; the maintainer policy path does not require Ruby.
- Missing tools or installed dependencies fail early with setup guidance.

`agent-tooling/update-skill-topology.sh` / `agent-tooling/sync-skill-surfaces.sh`
- Public commands and private topology core are Bash; topology reconciliation neither invokes nor requires Node. `sync-skill-surfaces.sh` is the offline distribute phase (matrix + surfaces). Browser-helper verification keeps its unrelated Node requirement.
- Default mode discovers repo-owned, Matt, Anthropic, neat-freak, visual-explainer, OpenAI Codex for Claude, Waza, and claude-mem inventories; validates matrix rows before any distribution write; regenerates marked manifest overrides for `Type: skill` sources; independently migrates legacy Codex-root drift; reconciles approved copies/plugins; performs owner-scoped cleanup; verifies the root plus every managed destination; then regenerates `agent-tooling/skills-matrix.md` from the verified state. Unmarked and other-owner active-surface entries remain untouched. `--check` never rewrites the matrix.
- Human mode streams discovery, planning, adapter, and verification progress to standard output, then prints a source/destination/change/result table; diagnostics stay on standard error, color is TTY-only, and `NO_COLOR` disables it. Add `--check` for a non-mutating preview or `--json` for one stable JSON document without human output. Exit codes: `0` reconciled/check-clean, `1` drift/adapter/verification failure, `2` invalid usage or manifest, `3` user decision required, `130` interrupted.
- OpenAI Codex is Claude-only; Waza and claude-mem are dual-plugin skills with manifest-scoped native Claude/Codex adapters and explicit expected skill identities. Check mode compares installed versions with each configured marketplace snapshot, confirms every declared skill through each native plugin install, and reports pending/blocked/verified migration gates plus retained and eventual duplicate-copy removals without mutation. Reconciliation removes tracked, untracked, managed, or edited copies of only the verified skill after both native paths pass; partial native success retains both copies, and cleanup failure remains visible without fallback delivery. Human and JSON output separate native reconciliation, runtime verification, retained copies, gated removals, and blocking failures; repeated healthy reconciliation reports clean/idempotent state. Recovery stays plugin-managed and is limited to upstream repair, native rollback, or an explicit manifest decision. Unknown installed third-party plugins return decision-required before mutation; Claude official and Codex system plugins are ignored. Claude-mem still requires runnable Bun, uv, and uvx and preserves the shared `~/.claude-mem` worker/database contract.
- Matt skills default to both surfaces, with `code-review` Codex-only because Claude supplies that built-in. Unknown npx lock sources return decision-required; `find-skills` is retired and its known lock/copy state is removed during reconciliation.
- Exit `3` means no distribution mutation occurred. Inspect `--check --json` decisions, make an explicit manifest or installed-state decision, then rerun; do not guess a fallback or delete unowned entries.

`agent-tooling/update-agents.sh`
- Updates the agent CLIs: `claude update` (native) and `npm install -g @openai/codex`.
- Tries both even if one fails; prints version before/after each.

Removed public commands: `update-repo-skills.sh`, `update-cc-plugins.sh`, `update-cli-skills.sh`, `update-waza.sh`, `update-claude-mem.sh`, `update-mattpocock-skills.sh`, `update-visual-explainer.sh`, `update-khazix-skills.sh`, and `update-anthropic-skills.sh`. No aliases or shims. Their mechanics now live only in `agent-tooling/distribution-topology/adapters/`.

Topology authoring:
- Refresh tracked `skills/` from the upstream `steipete/agent-scripts:main` mirror; do not add fork-only content there. Mirrored skills default to Claude.
- Put repo-owned Codex-only skills under `codex-skills/`; they default to Codex.
- Select Claude/Codex destinations by editing `Y`/`N` on `Type: skill` rows in `agent-tooling/skills-matrix.md`; generated override blocks in `agent-tooling/skill-topology.json` are not hand-edited.
- Resolve every reported new/removed skill row explicitly before reconciliation. Plugin rows are report-only; editing their destination cells blocks the run.
- For an external skill-bearing source, add exactly one `agent-tooling/skill-topology.json` source and one private adapter registration with its matrix source identity. Stage source-only and npx-only inventories under the matching `other-skills/<owner>/`; never write them directly into `skills/`. Record source defaults and plugin policy in the manifest; never add another public updater.
- Preview surfaces offline with `agent-tooling/sync-skill-surfaces.sh --check`; run `agent-tooling/sync-skill-surfaces.sh` to distribute and regenerate the matrix report; full single-pass remains `agent-tooling/update-skill-topology.sh`. Then run `agent-tooling/verify.sh` before commit.

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
