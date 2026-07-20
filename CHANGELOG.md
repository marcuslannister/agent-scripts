---
summary: Timeline of guardrail helper changes mirrored from Sweetistics and related repos.
---

# Changelog

## Unreleased

- Added a secret-safe Codex direct-API preflight so million-token launches fail before an unauthenticated Responses request when a machine is missing its Keychain delivery copy.

## 2026-07-17 — 0.12.0

### Highlights
- Turned `maintainer-orchestrator` into a long-running control plane for autonomous queue triage, proof-driven changes, dependency maintenance, and release proposals across Peter's repositories.
- Added fleet maintenance, safe repository synchronization, package ownership audits, and Xcode fleet management for Peter's Macs.
- Replaced the old Codex review path with isolated structured autoreview and added Claude Code-only `codex-first` delegation for implementation-heavy work.
- Added `scripts/sync-skills` so Codex and Claude share one canonical skill and instruction mirror across agent-scripts, manager, and repo-owned skills.
- Hardened 1Password, npm, and macOS release workflows around scoped service access, stable tool identities, noninteractive signing, and verified publication boundaries.

### Maintainer Orchestration
- Expanded `maintainer-orchestrator` with one tracked Codex thread per repository, 30-lane scheduling, durable status, forgotten-work preservation, exact-head landing, dependency sweeps, VISION capture, and release-readiness proposals.
- Added a dedicated OpenClaw mode with root-owned discovery, qualified execution lanes, contributor routing, live permission checks, serialized landing, and OpenClaw-specific proof and changelog rules.
- Added autonomous GitHub queue triage with URL-first item briefs, maintainer-comment routing, author context, live proof requirements, safe spam closure, and explicit Peter decision briefs.
- Added the non-majority repository ledger, owner-maintained crawl-family overrides, and clearer root ownership for orchestration policy and worker titles.
- Made dependency updates, internal operating repositories, bounded cleanup, safe dirty fast-forwards, and candidate-scoped release blockers autonomous.
- Improved ClawSweeper status reporting for worker capacity, exact-review occupancy, workflow waiters, bounded API reads, and accurate failure and closure counts.
- Tightened shared agent policy around exact-head proof, contributor credit, screenshot safety, post-merge recaps, background-task visibility, public mutation, and release authority.

### Review and Agent Workflows
- Replaced `codex-review` with structured `autoreview`, adding isolated Codex, Claude, and Pi review, safe bundle validation, regression provenance, security checks, parallel tests, and bounded multi-pass review.
- Added Claude Code-only `codex-first` routing for implementation, fixing, exploration, rebasing, and landing mechanics, including safe use of the ChatGPT app-bundled Codex CLI. Thanks @notorious-d-e-v.
- Added current model, effort, fast-mode, liveness, deterministic resume, and self-delegation guardrails to the Codex workflow.
- Made GitHub deep review and project triage prefer current source, real behavior reproduction, exact PR heads, and factual contributor trust signals.
- Routed screenshot and login-dependent browser work through existing Chrome state, with safe attach recovery and no silent isolated-browser fallback.
- Added explicit compatibility contracts, clean bounded-refactor guidance, generated-code skepticism, and scoped opportunistic cleanup rules.

### Fleet, Release, and Remote Operations
- Added `fleet-maintenance` for host health, package updates, repository synchronization, ownership collisions, disk cleanup, and service-impact reporting.
- Added `xcode-sync` for signed Xcode inventory, stable and prerelease slot management, build-identity checks, platform compatibility, and verified installation.
- Added dependency-light fleet repo audit and update helpers with batched snapshots, clean fast paths, dirty-work preservation, collision checks, and safe fast-forwards.
- Added `release-mac-app` and shared macOS release helpers for changelog notes, Sparkle appcasts, signing, notarization, GitHub assets, and post-release verification.
- Hardened macOS releases for passwordless isolated keychains, preloaded secrets, modern distribution validation, Bash 3.2, lightweight tags, bracketed changelog versions, and archive version parsing.
- Refreshed remote-Mac topology and network-boundary guidance, signed local app testing, locked-Mac Git fallback, and Cloudflare-only ClickClack deployment.
- Kept GitHub reads on the Octopool shim and added cache-health recovery before live GitHub fallback.

### Credentials and Safety
- Unified 1Password work on one tracked tmux session with scoped service-account access first, consent-gated desktop fallback, exact-field reads, known-item routing, and TCC-safe `~/bin/op` updates.
- Unified npm authentication around reusable service sessions, safe field selection, token caching, login fallback, package reservation, publication verification, and a generic authenticated command wrapper.
- Added internal-information, confidentiality, device-aware image upload, API-key storage, and approved-destination guardrails without blocking authorized private research.
- Standardized the canonical test Gmail account, OpenClaw deployment account, personal versus corporate Mac routing, and pre-approved Gmail service login behavior.

### Skills and Tools
- Added `scripts/sync-skills` to build Codex whole-root links, Claude's flat skill mirror, shared instruction pointers, deterministic collision handling, and stale-link pruning.
- Added skills for fleet maintenance, Xcode sync, Codex delegation, Twilio SMS, Wrangler, Things, Reminders, SSH diagnosis, agent transcripts, and shared macOS releases.
- Added `skill-cleaner` inventory, duplicate, usage, and prompt-budget audits plus isolated `--root-only` scans. Thanks @its-How.
- Added browser-tools network capture with filtering and follow mode. Thanks @mvanhorn.
- Hardened browser-tools startup, profile copying, symlink handling, and console flags. Thanks @ShiroKSH.
- Fixed xurl's OpenClaw npm installer metadata. Thanks @not-stbenjam.
- Made skill validation explicitly UTF-8-safe under C locales. Thanks @chaochaoweb3.
- Added skills.sh grouping metadata for shared skills. Thanks @vyctorbrzezowski.
- Exposed shared behavior validation, session viewing, crabbox, and crawl-family skills through the canonical mirror while removing duplicated bundled copies.

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
