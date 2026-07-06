---
summary: Timeline of guardrail helper changes mirrored from Sweetistics and related repos.
---

# Changelog

## 2026-07-06 — Windows CRLF Fixes
- Fixed `update-cc-plugins.sh` to strip Windows CRLF carriage returns from installed plugin keys before calling `claude plugin update`, preventing false "not found in marketplace" skips.
- `update-mattpocock-skills.sh` now parses the skills lock with `jq` (with an explicit jq presence check) instead of Windows Python and strips CRLF from skill names before copying, preventing false missing-entry and missing-source warnings.

## 2026-07-06 — Matt Skills Block Refresh
- Refreshed the `# matt-skills` `.gitignore` block for three new upstream skills (`migrate-to-shoehorn`, `scaffold-exercises`, `setup-pre-commit`) picked up by `update-mattpocock-skills.sh`.

## 2026-07-05 — Claude Mem Bun Guard
- `update-claude-mem.sh` now checks that Bun and Astral `uv` are installed/discoverable and runnable before installing or updating claude-mem, including Scoop installs whose shims may be broken, because its hooks and vector search depend on those tools.

## 2026-07-05 — CLI Skills Cleanup Fix
- Fixed `update-cli-skills.sh` legacy Waza removal on current `skills@latest`, which rejects `--agent '*'`; the cleanup now targets the shared Codex/global skill store and has a regression check.

## 2026-07-04 — Copies Everywhere: Plugin/Skill Update Rules Enforced
- Codified the plugin & skill update rules in `CLAUDE.md` (destination principle + four source classifications) and captured the vocabulary in a new `CONTEXT.md`.
- Waza moved from the skills CLI to each CLI's plugin marketplace (umbrella `waza@waza` plugin on both Claude Code and Codex, skills namespaced `/waza:think` etc.) via new `scripts/update-waza.sh`; its 8 skills-CLI installs and 8 tracked `skills/` symlinks were removed. `update-waza-skills.sh` became `update-cli-skills.sh` — just the skills.sh global update plus untracked `find-skills` copy sync (its tracked symlink is gone too).
- All remaining third-party symlinks converted to rsynced untracked copies behind marker-delimited `.gitignore` blocks: `neat-freak` (khazix), `docx`/`xlsx`/`pdf`/`pptx` (anthropic) in `skills/`; `frontend-design`/`skill-creator`/`visual-explainer` in `~/.agents/skills`. New shared helper `scripts/lib-copies.sh` (rsync + gitignore-block regen, replaces legacy symlinks in place) supersedes the deleted `lib-links.sh`; `update-mattpocock-skills.sh` now uses it too. `update-all.sh` gained a `waza` step and the renamed `cli-skills` step.
- Post-review hardening of the copy/plugin machinery: `install_skill_copy` falls back to `cp -R` when rsync is missing (Windows Git Bash), refuses to overwrite directories it did not create (`.agent-scripts-copy` ownership marker, adopting copies older updaters generated — lib-links fallback markers and pre-marker rsync copies matching upstream), and `regen_gitignore_block` refuses to rewrite an unterminated block instead of eating `.gitignore` to EOF; `.gitignore` entries are now derived from copies on disk so a transient sync failure can't surface third-party files as trackable; `update-cli-skills.sh` bootstraps `find-skills` (vercel-labs/skills) and removes legacy tw93/Waza skills-CLI installs on machines that still have them; new `scripts/lib-plugins.sh` (anchored marketplace matching, installed-but-disabled detection) replaces the duplicated marketplace choreography in `update-waza.sh` and `update-claude-mem.sh`; new `tests/lib-copies-test.sh` covers the copy guards and gitignore regen.

## 2026-07-04 — Matt Skills as Untracked Copies
- Reworked Matt Pocock skill distribution: dropped the 22 tracked symlinks from `skills/`; new `scripts/update-mattpocock-skills.sh` (wired into `update-all.sh`) bootstraps `mattpocock/skills` with `--agent codex` and rsyncs all its entries (34, per the CLI lock file) from `~/.agents/skills` into `skills/` as gitignored copies for Claude Code, regenerating a `# matt-skills` block in `.gitignore` each run. Only `code-review` stays Codex-only (collides with Claude's built-in `/code-review`); `update-skills.sh` was renamed to `update-waza-skills.sh` and is back to Waza bootstrap + global update only.

## 2026-07-04 — Engineering Skills Config
- `update-skills.sh` now bootstraps `mattpocock/skills` (Codex-only via `--agent codex`): canonical copies in `~/.agents/skills` serve Codex; the CLI no longer writes Claude links (the 37 blanket links were removed). Claude Code instead gets a curated set of 21 tracked symlinks in `skills/` — the full engineering suite plus `tdd`, `teach`, `wizard`, `ask-matt`, `claude-handoff` — while the rest stay Codex-only: `code-review` (built-in clash), `obsidian-vault` (vs `obsidian`), `edit-article`/`writing-*` (vs Waza `write`), `grilling`/`grill-*` (vs Waza `think`), `research` (vs Waza `learn`), `loop-me` (vs built-in `loop`), `writing-great-skills` (vs `skill-creator`), `git-guardrails-claude-code` (repo has its own guardrails), and the TypeScript-course-specific `scaffold-exercises`/`migrate-to-shoehorn`/`setup-pre-commit`.
- Replaced the repo's own `handoff` skill with a symlink to Matt Pocock's `handoff` (`~/.agents/skills/handoff`, installed by the skills CLI); the old version remains in git history.
- Ran `/setup-matt-pocock-skills`: added project-scoped `CLAUDE.md` (root `AGENTS.MD` stays global-only) with the `## Agent skills` pointer block, plus `docs/agents/{issue-tracker,triage-labels,domain}.md` — GitHub Issues via `gh` (external PRs not a triage surface), default five-label triage vocabulary, single-context domain docs.

## 2026-07-04 — Windows Update Script Fixes
- Updated Claude plugin refresh to parse installed plugins with `jq`; added a shared link helper for update-all skill refreshes that uses tracked Git symlink entries for repo skills and guarded copy fallback for Codex-only skill links; skipped Codex npm/plugin reinstalls when the installed version already matches; retried transient Codex marketplace refresh failures.

## 2026-07-03 — Rules Cleanup
- Removed the dead `gitcrawl gh` shim reference from `AGENTS.MD` (tool no longer exists on this machine); kept the standalone `gh api search/* --method GET` rule. Synced the same edit into `codex-settings/AGENTS.md`.

## 2026-07-03 — claude-mem Updater
- Added `scripts/update-claude-mem.sh`: installs/updates `thedotmack/claude-mem` for both Claude Code (marketplace `thedotmack`, `claude plugin marketplace add/update` + `claude plugin install/update`) and Codex (marketplace `claude-mem-local`, `codex plugin marketplace add/upgrade` + `codex plugin add`) purely via each CLI's plugin marketplace — no npx installer. Wired it into `scripts/update-all.sh` with its own summary line.

## 2026-07-03 — anthropic-skills Updater
- Added `scripts/update-anthropic-skills.sh`: clones/pulls `anthropics/skills` into `~/Projects/anthropic-skills` and links `frontend-design`, `docx`, `xlsx`, `pdf`, `pptx`, and `skill-creator` into `skills/` with tracked relative symlinks so they follow pulls. Wired it into `scripts/update-all.sh` with its own summary line.
- `frontend-design` and `skill-creator` now link into `~/.agents/skills` (Codex-only, visual-explainer style): Claude Code ships both via plugins and reads only the shared `skills/` dir, while Codex reads `~/.agents/skills` directly, so Codex tracks the upstream clone without duplicating the plugins.

## 2026-07-03 — khazix-skills Updater
- Added `scripts/update-khazix-skills.sh`: clones/pulls `KKKKhazix/khazix-skills` under `~/Projects` and links its `neat-freak` skill into `skills/` with a tracked relative symlink so it follows pulls. Wired it into `scripts/update-all.sh` with its own summary line.

## 2026-07-03 — CI Gates + Broken Skill Symlink
- CI now runs `scripts/validate-skills` (skill front matter) alongside the existing shell-syntax and transcript smokes.
- Removed the broken `skills/video-use` symlink; its target repo (`~/Projects/video-use`) no longer exists. Dropped it from the README skill list.
- Removed the broken `skills/improve-claude-md` symlink; its target (`~/.agents/skills/improve-claude-md`) no longer exists (superseded by the `review-claudemd` skill).

## 2026-07-02 — Codex-only visual-explainer Link
- Updated `scripts/update-visual-explainer.sh` to link visual-explainer under Codex's user skill root, `~/.agents/skills/visual-explainer`, and stop copying prompts or touching Claude Code.

## 2026-07-02 — Remove Codex Plugin Marketplace Updater
- Removed the obsolete Codex plugin marketplace updater, its `update-all` step, and its test because Codex should not refresh Claude plugin marketplaces as if those plugins were directly usable.

## 2026-07-01 — visual-explainer Updater
- Added `scripts/update-visual-explainer.sh`: clones/pulls `nicobailon/visual-explainer` under `~/Projects` (no `/tmp`), links the skill into `~/.codex/skills` with a relative symlink so it tracks pulls, and copies its prompt templates into `~/.codex/prompts`. Wired it into `scripts/update-all.sh` with its own summary line.

## 2026-06-20 — Video Use Skill Symlink
- Added `skills/video-use` as a tracked repo-owned skill symlink.

## 2026-06-19 — Agent Skills Updater
- Added `scripts/update-skills.sh` (bootstraps the Waza skill package `tw93/Waza` via `npx skills` when missing, then `skills update --global`) and wired it into `scripts/update-all.sh` as a third step. Treats the skills CLI's `Failed to …` output as a failure since the CLI still exits 0 on partial failures.

## 2026-06-16 — Agent Update Scripts
- Added `scripts/update-agents.sh` (updates Claude Code via `claude update` and Codex via `npm install -g @openai/codex`) and `scripts/update-all.sh` orchestrator that also runs `update-cc-plugins.sh`, runs every step without fail-fast, and prints a pass/fail summary. Written in bash (portable to Windows git bash).

## 2026-05-28 — 1Password Timeout Escalation
- Added AGENTS guidance to use `sag` to call Peter aloud when interactive 1Password unlock/sign-in times out, keeping the tmux session alive for retry.

## 2026-05-26 — Browser Network Capture
- Added `network` to `scripts/browser-tools.ts` for tailing DevTools request, response, and failure events from the active tab, with resource-type filters, color control, one-shot captures, and follow mode. Thanks @mvanhorn.

## 2026-05-25 — Agent Skills Origin
- Added `wrangler` skill for Cloudflare account routing, current Wrangler flags, KV/tail pitfalls, and serial command hygiene.
- Updated `skill-cleaner` to realpath-dedupe roots, keep Dropbox archives opt-in, print Codex-rule GPT-5.5 2% budget usage, scope disabled-plugin parsing correctly, and rank duplicate delete suggestions by body similarity with Codex/system copies preferred.
- Added `skill-cleaner` for auditing loaded Codex/OpenClaw skills, duplicate copies, recent usage, and prompt-budget description candidates.
- Renamed release workflow skills to the `release-*` convention and moved product-specific release skills into their owning repos.
- Added AGENTS guidance that `../agent-skills` means `openclaw/agent-skills`, plus local `handoff` skill routing.

## 2026-05-24 — 1Password Item Lookup
- Updated `one-password` to allow explicit vault-scoped metadata search for fuzzy/screenshot-driven item lookup before exact field reads.

## 2026-05-23 — Skill Description Budget
- Shortened skill frontmatter descriptions to terse trigger phrases so the skills prompt budget keeps useful routing hints without filler prose.
- Updated `gog` auth guidance to preserve broad user OAuth scopes during reauth and rely on command guards for scoped execution.

## 2026-05-22 — Browser UI Verification
- Added hard guidance to verify screenshot/live UI bugs through the existing Chrome `$browser-use` path, including one-shot Peekaboo acceptance for visible Chrome attach alerts and no silent Playwright fallback for login/profile-dependent pages.

## 2026-05-22 — npm Release Auth
- Updated `npm` to treat explicit release/publish requests as consent for the expected desktop 1Password npm auth prompt when service-account access cannot read `npmjs`, while still stopping on missing or ambiguous credentials.

## 2026-05-22 — Auto Review Skill
- Replaced the old `codex-review` skill with `autoreview`, keeping Codex as the default/recommended review engine while adding structured findings, prompt/dataset inputs, tool/web-search review context, and security-aware checks.

## 2026-05-21 — Mac App Release Skill
- Added `release-mac-app` skill and `mac-release` helper so Sparkle appcast, key validation, GitHub release asset checks, and release closeout are shared while app metadata stays in each repo’s `.mac-release.env`.

## 2026-05-20 — Browser Login Automation
- Updated `browser-use` to prefer existing Chrome for login-heavy sites because isolated profiles trigger captcha/device checks.

## 2026-05-20 — OpenClaw Deployment Account
- Added AGENTS routing to require `service@openclaw.org` accounts for OpenClaw deployments.

## 2026-05-20 — Things Todo Skill
- Added `things-todo` skill for Things 3 todo CRUD through the `things` CLI with auth-token handling, JSON/read-back verification, and no direct DB-write guidance.

## 2026-05-20 — Reminders Skill
- Added `reminders` skill for Apple Reminders CRUD through the `rem` CLI with JSON/read-back verification and macOS permission notes.

## 2026-05-20 — GitHub Triage Skill Detail
- Updated `github-project-triage` to summarize each issue/PR with fit, risk, proof, blockers, next action, and contributor trust signals.
- Added a bundled `github-activity.sh` helper for repo/global GitHub author activity checks during triage.

## 2026-05-20 — Codex Review Autoreview Trigger
- Updated `codex-review` skill description to include `autoreview` for routing/search.

## 2026-05-18 — 1Password Exact Field Reads
- Updated `one-password` to avoid tmux window-index assumptions and document exact-label JSON extraction when `op --field` resolves an ambiguous concealed field.

## 2026-05-18 — SSH Doctor Skill
- Added `ssh-doctor` for Remote Login diagnosis, launchd sshd pre-auth closes, stale `sshd-session` cleanup, and safe OP profile token block checks.

## 2026-05-18 — 1Password Service Account Priority
- Updated `one-password` to prefer scoped service-account access before interactive desktop-app sign-in and to ask before fallback when scoped access is missing.

## 2026-05-18 — Browser Reattach Defaults
- Updated `browser-use` to call the default mcporter `chrome-devtools` reattach target without a temporary config file.
- Added browser-use mcporter config notes for diagnosing blank/isolated Chrome attachments and restoring the reattach config.

## 2026-05-18 — Lean Fix Guidance
- Added AGENTS guidance to prefer clean bounded refactors over tiny shims and avoid compat/edge-case scaffolding except for real public/API, upgrade, security, or production states.

## 2026-05-16 — Codex Review Gitcrawl Repair
- Extended `codex-review` Gitcrawl recovery guidance to inspect portable manifest, source/runtime DB health, and portable-store status before live fallback.
- Updated `codex-review` to run `gitcrawl doctor --json` for malformed local Gitcrawl DB errors before falling back to live GitHub reads.

## 2026-05-16 — GitHub Project Triage Scope
- Updated `github-project-triage` to default broad queue scans to `steipete` and `openclaw`, sort PR triage by PR count, and preserve RepoBar order when summarizing.

## 2026-05-14 — Video Transcript Dependency Update
- Updated `video-transcript-downloader` to `youtube-transcript-plus` 2.0.0.

## 2026-05-14 — Codex Review Finding Detection
- Updated `codex-review` to capture review output, report elapsed time, fail on reported P0-P3 findings, and treat empty review output as non-clean.

## 2026-05-14 — Codex Review Full Access
- Added `codex-review --full-access` for nested review runs that need localhost bind/listen tests without sandbox noise.

## 2026-05-14 — GitHub Search Shim Guidance
- Added AGENTS guidance to prefer shimmed `gh` / `gitcrawl gh` for broad reads and avoid raw Search API POST mistakes.

## 2026-05-14 — Codex Review Base Caveat
- Documented that `codex review --base` must not include an inline prompt; use a separate follow-up pass for custom instructions.
- Clarified that committed or PR branch review must use branch/base mode, not `--uncommitted` / local mode.

## 2026-05-14 — Codex Review Loop Guidance
- Clarified that `codex-review` should iterate until no accepted findings remain and document intentional rejections with useful inline comments when warranted.

## 2026-05-14 — README Skills Overview
- Rewrote the README around agent instructions, skills, helper scripts, and sync expectations; removed stale copied-origin notes.

## 2026-05-14 — Codex Review Skill
- Added a `codex-review` skill and helper for closeout reviews, with stdout-only default output and subagent filtering guidance for noisy review output.

## 2026-05-13 — Checkout Discipline
- Added CLI checkout/worktree guardrails: stay in repo cwd by default, never create worktrees unless asked, and treat sibling checkouts under `~/Projects` as user-managed.

## 2026-05-13 — Skill Metadata Guardrails
- Added generic skill-description guidance and quieter browser recovery notes to reduce noisy auth prompts and token-heavy skill metadata.

## 2026-05-11 — clawmac GUI Access Note
- Documented the Peekaboo through Jump Desktop workflow for clawmac GUI prompts and Chrome Safe Storage verification.
- Documented `crabmac` as Peter's typo/alias for `clawmac`.

## 2025-12-22 — Remove Custom rm Shim
- Dropped `bin/rm` and `scripts/trash.ts`; rely on the system `trash` command for recoverable deletes.

## 2025-12-17 — Remove Runner; Keep Guardrails
- Removed the `runner` wrapper and `scripts/runner.ts` now that modern Codex sessions handle long-running/background work directly.
- Kept the safety-critical bits as standalone shims: `bin/rm` (moves deletes to Trash via `scripts/trash.ts`).
- Dropped the `find -delete` interception and the `bin/sleep` shim.

## 2025-12-02 — Release Preflight Helpers
- Added shared release helpers in `release/sparkle_lib.sh`: clean working-tree check, Sparkle key probe, changelog finalization/notes extraction, and appcast monotonicity guard for version/build.
- Documented the helper functions in `docs/RELEASING-MAC.md` so Trimmy/CodexBar-style release scripts can reuse them.

## 2025-11-18 — Console Log Capture
- Added `console` command to `scripts/browser-tools.ts` for capturing and monitoring Chrome DevTools console output with real-time formatting, type filtering (log, error, warn, etc.), continuous follow mode, and configurable timeouts with automatic object serialization.

## 2025-11-22 — Search & Content Extraction
- Added `search` and `content` commands to `scripts/browser-tools.ts` for Google SERP scraping with optional readable markdown extraction and single-URL readability output, leveraging the existing DevTools-connected Chrome instance.
- `eval` now supports `--pretty-print` to inspect complex objects with indentation and colors.

## 2025-11-15 — Chrome Browser Tools
- Added `scripts/browser-tools.ts`, a DevTools-ready Chrome helper copied from the Oracle repo so agents can inspect, screenshot, and terminate sessions without dragging in the full CLI. The workflow is inspired by Mario Zechner’s [“What if you don’t need MCP?”](https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/).
- Documented the new helper in the README so downstream repos know how to run `pnpm tsx scripts/browser-tools.ts --help`.

## 2025-11-16 — Browser Tools Pipe Detection
- Updated `scripts/browser-tools.ts` to enumerate and kill Chrome instances started with `--remote-debugging-pipe` (the default for Peekaboo/Tachikoma) in addition to the classic `--remote-debugging-port`. List/kill now show “debugging pipe” when no port exists and still fetch tab metadata when it does.
- README now notes the optional `NODE_PATH=$(npm root -g)` trick so the helper can run from bare copies of the repo without a local `package.json`.

## 2025-11-14 — Compact Runner Summaries
- The runner's completion log now defaults to a compact `exit <code> in <time>` format so long commands don't repeat the entire input line.
- Added the `RUNNER_SUMMARY_STYLE` env var with `compact` (default), `minimal`, and `verbose` options so agents can pick how much detail they want without editing the script.
- Timeout heuristics now understand both `pnpm` and `bun` invocations automatically, so long-running Bun scripts/tests get the same guardrails without repo-specific patches.
- `sleep` invocations longer than 30 seconds are clamped to the 30s ceiling instead of erroring, which keeps wait hacks working while still honoring the AGENTS.MD limit.

## 2025-11-08 — Sleep Guardrail & Git Shim Refresh
- Runner now rejects any `sleep` argument longer than 30 seconds, mirroring the AGENTS rule and preventing long blocking waits.
- Added `bin/sleep` so plain `sleep` calls automatically route through the runner and inherit the enforcement without extra flags.
- Simplified `bin/git` to delegate directly to the runner + system git, eliminating the bespoke policy checker while keeping consent gates identical.

## 2025-11-08 — Guardrail Sync & Docs Hardening
- Synced guardrail helpers with Sweetistics so downstream repos share the same runner, docs-list helper, and supporting scripts.
- Expanded README guidance around runner usage, portability, and multi-repo sync expectations.
- Added committer lock cleanup, tightened path ignores, and refreshed misc. helper utilities (e.g., `toArray`) to reduce drift across repos.

## 2025-11-08 — Initial Toolkit Import
- Established the repo with the Sweetistics guardrail toolkit (runner, git policy enforcement, docs-list helper, etc.).
- Ported documentation from the main product repo so other projects inherit the identical safety rails and onboarding notes.
