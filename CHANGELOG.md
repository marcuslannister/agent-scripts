---
summary: Timeline of guardrail helper changes mirrored from Sweetistics and related repos.
---

# Changelog

## Unreleased

- Refreshed staged third-party skills (anthropics f6656c1, humanlayer 3c26291, khazix 299e201, matt 068b6e0, nicobailon ff8cd15) and regenerated the selection-preserving skills matrix.

- Refreshed staged third-party skills (anthropics f6656c1, humanlayer 3c26291, khazix 299e201, matt 068b6e0, nicobailon ff8cd15) and regenerated the selection-preserving skills matrix.

- Adopted ADR-0009: tooling manages tracked skill content only, native plugins become user-managed per-machine state with a best-effort refresh helper, and the topology engine's replacement by a staging-only acquire is decided; glossary updated accordingly.

- Replaced the topology engine and its private-adapter protocol with a staging-only `update-skill-topology.sh` (~3,550 lines deleted) whose check mode distinguishes install, update, and remove, and merged `skill-topology.json` and `registry.json` into one `agent-tooling/sources.json`; a routine acquire now reconciles in about ten seconds instead of twenty-two minutes.

- Added `agent-tooling/update-plugins.sh`: best-effort native plugin refresh on every machine that skips permanently failing marketplaces (ADR-0007), reports an unreadable plugin inventory instead of silently skipping every update, and never fails the run.

- One command per machine: `update-all.sh` now ships by default (`--no-ship` for a review run) and `update-local.sh` fast-forward pulls before updating, so secondary machines — including Windows under Git Bash — need a single command. Retired `scripts/sync-skills` to a refusing stub.

- Added `agent-tooling/repair-codex-registry.sh`: report the Codex marketplaces and plugins this repo expects, and re-register with `--fix` the ones Codex has lost. Operator-run through `codex` commands only, never wired into the updaters (ADR-0007).

- Cached plugin-source clones under `~/.cache/agent-scripts/source-clones/`, so acquire refreshes one shallow clone per source instead of cloning every marketplace repository again on each run; check mode stays hermetic.

- `agent-tooling/update-agents.sh` now runs `pi update --extensions` after `pi update`, so installed Pi packages stay current with the CLI.

- Added an upstream-complete root overlay: preserve every recorded `steipete/agent-scripts:main` path while keeping local additions and modifications, with a clean-worktree sync command and offline verification.

- Added headless Sparkle signing through scoped 1Password references, with public-key validation, mode-0600 temporary files, and cleanup on success or failure.

- Added explicit Ship mode to `update-all.sh`: require a clean worktree, pull first, run and validate the update, record the changelog, commit, push, pull with fast-forward only, and verify the final state.

- Refreshed staged Anthropic, HumanLayer, Khazix, Matt Pocock, and visual-explainer skills, generalized the `refresh-mac` trigger, and regenerated the selection-preserving skills matrix.

- Updated `agent-tooling/update-agents.sh` to install Pi with its native installer when missing and run `pi update` when present.

- Added `refresh-mac` for Claude and Codex: keep project pulls and Trash cleanup, apply the Nix Darwin configuration, and leave Nix-managed Homebrew unchanged.

- Reconciled `steipete/agent-scripts` through `067178d`: refreshed shared skills, added `codexbar`, `telecrawl`, and `project-structure`, updated fleet and release checks, corrected GitHub secret stdin guidance, and removed the obsolete scoped commit helper.

- Stopped acquire retrying a Codex marketplace refresh that can never succeed: `codex plugin marketplace upgrade` re-clones the whole upstream repo under a hardcoded 30s timeout, so `thedotmack/claude-mem` (~330MB, ~44s) fails identically on all three attempts and reported the same error three times. The adapter now recognises the clone-timeout signature, stops after the first attempt, and names ADR-0007 and the manual repair; failures that could be transient keep the full retry budget.

- Fixed `agent-tooling/update-local.sh` never updating native plugins, which froze them at whatever version a secondary machine first installed (observed: `mattpocock-skills` stuck at 1.2.0 against upstream 1.2.3, plus claude-mem and Waza). Plugin reconciliation lived only in the acquire phase, which `update-local.sh` skips because acquire also mirrors tracked staging — but plugins are per-machine CLI state that git never carries, so distribute reported success while the plugins stayed stale. Acquire gains `--plugins-only`, which narrows every source loop to registry entries owning a native plugin and writes no staging, and `update-local.sh` now runs it between the CLI and distribute steps.

- Fixed `sync-skill-surfaces.sh` permanently erroring on a selected skill whose surface copy predates the marker era: the planner rejected every unmarked directory outright, even though `install_skill_copy` would have adopted it, so a pre-marker copy could never gain a marker and the run failed on each pass. Both layers now share one `copy_is_adoptable` predicate, and a directory with planned drift is no longer also reported as preserved.

- Refreshed staged third-party skills and author index, adding Matt Pocock's `wait-what` and `writing-for-agents` while retiring eight Codex selections removed upstream.

- Fixed `agent-tooling/update-agents.sh` leaving Codex permanently unusable after an interrupted install: npm retires the Codex launcher before fetching the ~126MB platform tarball and only restores it on success, so a killed run dropped `codex` off `PATH` and every later run re-downloaded the whole tarball instead of recovering. The Codex step now restores a present-but-unlinked package on Unix and Windows Git Bash (falling through to a real reinstall if the tree is truncated), which also lets the existing up-to-date check skip the download.

- `agent-tooling/update-agents.sh` now installs Claude Code (native installer) and Codex (`npm install -g @openai/codex`) when the binary is missing from `PATH`, instead of only updating an existing install; verifies the binary is runnable after install before reporting success.

- Added `agent-tooling/update-local.sh`: agent CLI updates + offline distribute only, for secondary machines that pull already-committed staging changes instead of running the network acquire phase; the topology cutover policy now recognizes and requires the public command.

- Ported the selection-preserving skills-matrix generator from Python to Bash/awk without changing its generated report, including Unicode character-based token estimates (#51).

- Collapsed acquire manifest and registry schema validation from 360 per-field `jq` launches to two single-pass invocations, removing the Windows Git Bash startup bottleneck while preserving diagnostics (#50).

- Replaced manifest-generated distribution overrides with direct, offline matrix reconciliation and selection-preserving matrix generation (#49).

- Kept skills-matrix output UTF-8 on Windows and preserved canonical npx source attribution after deliberate legacy lock removal.

- Stopped stale report-only plugin rows from blocking skill-surface reconciliation after their local plugin caches are removed; live plugin destination edits still require a decision.

- Migrated legacy Claude skills-root pointer files into collision-safe backups before creating the managed per-skill surface, fixing Windows distribution failures.

- Dropped the staged `skill-creator` Codex copy (matrix row now `N|N`); Claude keeps it through the native `claude-plugins-official` plugin.

- Fixed `generate-skills-matrix.py` folding the staged `anthropics/skills` `skill-creator` copy into the `claude-plugins-official` plugin row once that plugin was installed locally: the registry's explicit `matrixSource` now wins over the plugin-name-collision fallback, which had blocked distribute with a spurious plugin-row-edit decision.

- Made `agent-tooling/update-skill-topology.sh` acquire-only (complete tracked staging + native plugins), changed `update-all.sh` to agent updates → acquire → offline distribute, and hardened verification against resurrected single-pass entry points (#47).

- Added offline distribute command `agent-tooling/sync-skill-surfaces.sh`: matrix validation/overrides/report, surface copies from tracked staging, orphan cleanup, Codex hygiene, and Claude root migration without network; missing selected staging content fails naming acquire/`git pull` (#46).

- visual-explainer Codex delivery stages under `other-skills/nicobailon/` with `.source.json`; surface marker points at staging; Claude stays native-plugin (#45).

- Deleted legacy npx skills-lock removal mutation; known npx lock entries now report `legacy-npx-lock-entry` decision-required with the lock left byte-identical (#44).

- Tracked foreign skill staging: `other-skills/<owner>/` is fully tracked with no staging gitignore blocks or per-skill `.agent-scripts-copy` markers; each source dir gets a refreshed `.source.json` (upstream repo, commit, sync time), and surface copies keep three-line markers pointing at the tracked staging path.

- Reserved GPT-5.6's maximum output budget in `codex-huge-context` and moved fleet compaction to a verified 922K input window with an 820K safety threshold.
- Made `codex-first` treat the Gorilla-backed Clawdex endpoint as already model-routed, preventing recursive Codex delegation after the fleet proxy migration.
- Added a secret-safe Codex direct-API preflight so million-token launches fail before an unauthenticated Responses request when a machine is missing its Keychain delivery copy.

## 2026-07-25 — Mattpocock/Humanlayer Governance Migration
- Generalized `npx-source.sh` to support multiple npx-only sources instead of hardcoding mattpocock/skills, and registered `humanlayer/skills`.
- Migrated 39 mattpocock skills from raw, stale npx installs to governed staged copies on codex.
- Staged humanlayer/skills' `improve-claude-md` but left it off codex — the installed copy diverged from upstream and the safety gate correctly declined to auto-adopt it.
- Reverted a bad `visual-explainer` dual-plugin reclassification that broke its custom adapter; removed `claude-code-setup`, `frontend-design`, and `superpowers` from codex as unmanageable via this tool's plugin adapters (shared multi-plugin marketplace repo, no per-plugin Codex manifest).
- Dropped the stale `remember` matrix row (confirmed uninstalled upstream) and refreshed khazix's `aihot` staged copy to current upstream.

## 2026-07-24 — Agent Tooling Folder
- Moved the skill/topology update machinery (`update-skill-topology.sh`, `update-all.sh`, `update-agents.sh`, `verify.sh`, `validate-skills`, `lib-copies.sh`, `generate-skill-index.sh`, `generate-skills-matrix.py`, the `test-*-policy` gates, `distribution-topology/`) plus `skill-authors.json`, `skill-topology.json`, and `skills-matrix.md` out of `scripts/`/`docs/`/repo root into a new `agent-tooling/` folder, leaving unrelated personal utilities (`committer`, `nanobanana`, `shazam-song`, `browser-tools.ts`, `docs-list.ts`, `trash.ts`) and the external `skills.sh.json` marketplace manifest where they were.

## 2026-07-24 — Khazix Staging Rename
- Fixed `khazix-skills` staging under `other-skills/khazix/` instead of the colliding `other-skills/marcus/` name (that bucket belongs to the unrelated `marcus`-authored repo-owned skills), and de-fragilized two tests that had asserted a specific live skill-selection value instead of manifest structure.

## 2026-07-24 — Live-Host Matrix Reconciliation
- Bootstrapped the real `~/.claude/skills` managed root, missing on this host since #38 landed, and reconciled it clean, closing #37.
- Trimmed the Claude/Codex skill selection to a curated subset via `docs/skills-matrix.md` hand-edits, applying the removals through the reconciler and regenerating the manifest override block.

## 2026-07-23 — Node Verification Toolchain
- Replaced the repo development Bun toolchain with Node.js 22.18+ and npm, migrating browser-helper tests and smoke verification while retaining claude-mem's external Bun runtime checks.

## 2026-07-23 — Foreign Skill Staging
- Moved source-only and npx-only inventories out of agent surfaces into owner-grouped `other-skills/{marcus,anthropics,matt}/`, tracking Marcus content while ignoring reproducible Anthropic and Matt copies (#34).
- Installed only manifest-selected staged skills per agent, using Claude plugins for plugin-classified sources and staged copies for Codex (#35).
- Split the generated skills matrix into manifest-derived Claude/Codex selections and attributed the tracked mirror to `steipete/agent-scripts` (#36).
- Replaced the repo-wide Claude skills symlink with a fail-closed managed directory of marker-verified per-skill copies (#38).
- Made `Type: skill` matrix rows the fail-closed selection input for repo-owned and foreign copies, generating marked per-source manifest overrides while rejecting inventory mismatches and plugin-row edits (#39).
- Folded skills-matrix report regeneration into successful topology reconciliation while keeping `--check` byte-preserving (#40).
- Recorded matrix type-keyed selection policy and corrected Claude-surface setup, routing, and glossary documentation (#41).

## 2026-07-23 — Upstream Skills Mirror
- Replaced tracked `skills/` with the exact 53-skill `steipete/agent-scripts:main` tree, refreshed author attribution, and retired the duplicate Codex-authored `maintainer-orchestrator` copy (#33).
- Made tracked mirror identities win copy-source overlaps and documented recovery of the pre-mirror tree plus reproducible ignored copies.

## 2026-07-21 — Dual-Plugin Skill Model
- Replaced the source-wide `plugin-both` classification with per-skill `dual-plugin` terminology in the glossary, topology manifest, adapter registry, and reporting fixtures.
- Required plugin bundle metadata to declare expected skill identities (`plugin.skills`) for later runtime verification; dual-native Claude/Codex reconciliation stays on the existing private adapter path.
- Verified dual-plugin bundles through native marketplace state, installed plugin paths, and every declared runtime skill on both Claude Code and Codex; missing runtime components now block verification without fallback delivery.
- Gated dual-plugin copy migration on both native runtimes, reporting retained/eventual removals in check mode and deleting only verified skill identities across managed, tracked, untracked, or edited copies without fallback delivery.
- Added phase-specific migration events, no-fallback recovery guidance, clean/idempotent repeat state, and post-migration regression proof that missing plugin skills never recreate copies.

## 2026-07-21 — Skill Author Index
- Added an explicit per-skill author registry (`skill-authors.json`, all 83 skills) and `scripts/generate-skill-index.sh`, which generates `INDEX.md` grouping every distributed skill by true upstream author; `skills/` stays flat (ADR-0003, #26). `--check` gates freshness and fails on any unattributed on-disk skill.
- Removed the remaining untracked onecli staging artifacts and their author-registry entries.
- Prevented Claude plugin command output from contaminating visual-explainer reconciliation records while preserving actionable mutation failures, aligned topology tests with Codex-only Anthropic overrides, and preserved explicitly disabled plugin state during freshness checks and updates.

## 2026-07-21 — Matt Skills Plugin Migration
- Split the Matt skills source into a Codex-only npx source and a Claude-only `mattpocock-skills` plugin source, moving Claude delivery from gitignored copies to the plugin marketplace while leaving Codex npx delivery unchanged.
- Added a marketplace-manifest version fallback that resolves the plugin's own `plugin.json` when the marketplace entry omits a version, and updated the topology real-manifest guard for the split.

## 2026-07-15 — Skill Retirement
- Removed the repo-owned `onecli-gateway` skill from Claude and Codex distribution.

## 2026-07-14 — Skill Topology Final Cutover
- Added the OpenAI Codex plugin as a manifest-managed Claude-only source.
- Prevented successful source-refresh output such as `Already up to date.` from contaminating the adapter inventory protocol and failing Anthropic, neat-freak, or visual-explainer reconciliation.
- Replaced the maintainer-orchestrator policy verifier with Bash, preserving its policy and diagnostic contract while removing its Ruby prerequisite and adding no-Ruby success and failure coverage.
- Replaced the private Node topology core with one Bash implementation, preserving public command behavior while adding no-Node command and topology-suite regression coverage.
- Reduced routine updates to agent CLIs then manifest-owned topology reconciliation, preserving ordered run-all execution, concise summary output, and aggregate failure behavior.
- Removed all legacy per-source updater commands and generic plugin policy code without shims; added a verifier gate that enforces the private adapter handshake and rejects restoration of bulk repo publication.
- Completed human topology reporting with live phase progress, one explicit source/destination/change/result table for every outcome, TTY-only color with `NO_COLOR`, and undecorated single-document JSON output.

## 2026-07-14 — Codex Root Hygiene and Instruction Setup
- Moved legacy `~/.codex/skills` migration and final verification into `update-skill-topology.sh` as an independent responsibility, with non-mutating checks, collision-safe timestamped backups, partial-failure reporting, safe reruns, and separate black-box coverage.
- Deleted the conflicting `sync-skills` mirror without a compatibility shim and added explicit idempotent `setup-agent-instructions.sh`, which owns only absent/shared instruction pointers and preserves real files and foreign symlinks.

## 2026-07-14 — Matt Skills Topology
- Added a manifest-scoped Matt skills adapter with both-surface defaults, a Codex-only `code-review` override, complete upstream/lock preflight, precise renamed/removed cleanup, partial-failure detection, and final verification.
- Retired generic global npx updates and `find-skills` bootstrap/distribution; unknown skills-lock sources now require a decision before mutation, while reconciliation removes only the known `find-skills` lock entry and owned copies.

## 2026-07-14 — Plugin-Distributed Skill Topology
- Added non-mutating native-plugin freshness checks against temporary remote marketplace clones, with planned-install/update reporting, fail-closed discovery, byte-preservation coverage, and reconcile-then-clean proof.
- Added manifest-scoped native adapters for Waza and claude-mem on Claude and Codex, preserving claude-mem dependency checks and shared state while gating unknown third-party plugins before mutation, ignoring bundled system plugins, aggregating failures, and verifying final state.
- Routine `update-all.sh` no longer invokes generic or direct plugin updaters; the generic Claude plugin entrypoint now delegates to manifest topology, while staged per-source entrypoints remain until final cutover.

## 2026-07-13 — Copy-Distributed Third-Party Topology
- Added manifest-owned adapters for Anthropic skills, neat-freak, and visual-explainer with complete preflight inventory, both-surface policy, non-mutating checks, idempotent reconciliation, owner-scoped cleanup, and final verification through `update-skill-topology.sh`.
- Anthropic's six managed skills and neat-freak now target both surfaces; visual-explainer keeps Claude's native plugin mechanism and a content-hashed Codex copy.

## 2026-07-13 — Repo-Owned Skill Reconciliation
- `update-skill-topology.sh` now reconciles by default, aggregates independent repo adapter failures, always verifies final managed state, and reports installs, removals, skipped unowned entries, and decisions; `--check` remains non-mutating.
- Moved `maintainer-orchestrator` to the Codex-only authoring source, retained `codex-first` as Claude-only and 21 explicit both-surface approvals, and limited first-run cleanup to disallowed copies marked `repo-skills` while preserving unmarked, other-owner, and approved entries.

## 2026-07-13 — Repo-Owned Skill Topology Preview
- Added strict versioned `skill-topology.json` policy for repo-owned source defaults and named Codex distribution exceptions.
- Added non-mutating `update-skill-topology.sh --check` with human/JSON reports, complete-plan validation, distinct recovery exit codes, temporary discovery, and stale-safe single-writer locking.

## 2026-07-13 — Routine Update Guard and Repository Verifier
- Routine `update-all.sh` runs no bulk repo-skills publication step; its black-box regression locks the supported updater order and excludes repo publication.
- Added `scripts/verify.sh` as the one local and CI verification interface for skill validation, Bash syntax, updater/copy regressions, maintainer policy, browser helper tests/build, and video-downloader smoke checks, with actionable dependency preflights.

## 2026-07-12 — AGENTS.MD Reconciliation
- Reorganized `AGENTS.MD` into Core / Routing / Project Defaults / PR-CI / Runtime Safety / Git sections, folding in reconciled upstream rules (`$codex-first` routing, `gitcrawl gh` read shim, zsh loop and `--no-gpg-sign` safety notes) while keeping the fork's own identity and internal/external disclosure rules.

## 2026-07-12 — Upstream Merge Reconciliation
- Merged `upstream/main` (steipete/agent-scripts). Kept the fork's own `AGENTS.MD`, one-skills-root-per-CLI model (ADR 0001), Python `validate-skills`, and the prior "unused skills" removals — honoring the modify/delete conflicts for `agent-transcript`, `browser-use`, `clawsweeper-status`, `clickclack`, `npm`, `one-password`, and `xurl`.
- Adopted from upstream: `maintainer-orchestrator` and `codex-first` skills, `scripts/sync-skills` and `scripts/test-maintainer-orchestrator-policy`, `browser-tools.ts` hardening, `package.json`/`bun.lock`, and the CI steps that build the browser helper and test the orchestrator worker boundary.
- Dropped upstream additions that don't fit the fork: `fleet-maintenance`, `xcode-sync`, and the broken sibling-repo symlink skills (`crabbox`, `gitcrawl`, `graincrawl`, `behavior-validator`, `session-viewer`).

## 2026-07-11 — Matt Skills Upstream Reconciliation
- `update-mattpocock-skills.sh` now reconciles the full `mattpocock/skills` set on every run, installing new skills and removing canonical and Claude-side copies deleted or renamed upstream instead of only refreshing names already present in the skills lock.
- Matt's generated ignore block moved from tracked `.gitignore` to repo-local `.git/info/exclude`, preventing upstream skill additions and renames from dirtying the worktree; the updater migrates the old tracked block after a successful sync.

## 2026-07-07 — Copy Drift Detection
- `.agent-scripts-copy` markers gain a third line: the copy's content hash (deterministic SHA-256 over non-hidden files) stamped by `install_skill_copy` at sync time. Best-effort — a valid two-line marker is still written when no `sha256sum`/`shasum` is available. All marker readers are line-addressed, so existing two-line markers stay valid and are re-stamped on their next sync.
- New `check_skill_copy_updates` in `lib-copies.sh` compares the stored hash against the current upstream source (→ upstream advanced since last sync) and the on-disk copy (→ copy hand-edited since install), reporting per skill and returning non-zero when a sync is warranted. It only reads.
- `update-khazix-skills.sh` and `update-anthropic-skills.sh` gain a `--check-updates` flag: pull the clone, report drift for their gitignored copies (both surfaces, for anthropic) without touching them, and exit non-zero as a `git diff --exit-code`-style gate. This is the only drift signal these copies have, since they are `.gitignore`d and never show in `git status`.
- Extended `tests/lib-copies-test.sh`: line-3 stamping, `compute_copy_hash` marker-independence and content-sensitivity, and `check_skill_copy_updates` upstream/tamper/missing/unstamped/empty cases. Added **sync-time hash** to `CONTEXT.md`.

## 2026-07-06 — Copy Sync Owner Markers
- Deepened the copy-sync recipe into one `sync_skill_copies` module in `lib-copies.sh` (owner, source_root, dest surface, gitignore-or-`""`, names): it installs marked copies, runs owner-keyed orphan cleanup, and regenerates the surface's `.gitignore` block behind a single interface. `update-cli-skills.sh`, `update-mattpocock-skills.sh`, `update-anthropic-skills.sh` (both surfaces), `update-khazix-skills.sh`, and `update-visual-explainer.sh` now call it instead of re-deriving the loop; `update-visual-explainer.sh` gains the orphan cleanup it never had (closes #3, subsumed by #8).
- `.agent-scripts-copy` markers are now two lines — upstream source path, then the owning updater id (`cli-skills`, `matt-skills`, `anthropic-skills`, `khazix-skills`, `visual-explainer`, `repo-skills`). Orphan cleanup keys on the owner, so `update-cli-skills.sh` and `update-mattpocock-skills.sh` (which share `~/.agents/skills` as a source and `skills/` as a surface) no longer read each other's `.gitignore` block to avoid deleting the sibling's copies. A pre-owner single-line marker is never deleted; it gets an owner line the next time its own updater re-syncs it. `update-repo-skills.sh` keeps its bespoke driver but writes and reads the two-line marker. The now-unused `gitignore_block_skill_names` cross-block reader was removed.
- Added `tests/update-khazix-skills-test.sh`; extended `tests/lib-copies-test.sh` with owner-marker, legacy-never-deleted, same-surface cross-owner protection, and `sync_skill_copies` cases; updated the cli/matt/anthropic/visual/repo suites for the two-line marker. Added **owner** to `CONTEXT.md`.

## 2026-07-06 — One Skills Root per CLI
- Root policy change: Codex now reads only `~/.agents/skills`; the tracked `~/.codex/skills → agent-scripts/skills` symlink was removed from codex-settings because Codex loaded both roots and saw duplicates of every synced skill (the Matt Pocock set, `find-skills`). New `scripts/update-repo-skills.sh` (wired into `update-all.sh`) rsyncs the repo's tracked skills into `~/.agents/skills` as marked copies; Claude Code keeps reading `skills/` live via `~/.claude/skills`. Recorded as ADR `docs/adr/0001-one-skills-root-per-cli.md`; CONTEXT.md vocabulary renamed to **Claude surface** / **Codex surface**.
- `update-repo-skills.sh` now migrates legacy `~/.codex/skills` drift into `~/.codex/skills-migrated-<timestamp>` instead of only failing the run: it moves old root symlinks, directories, symlinks, and plain pointer files while excluding `.system`, leaves `~/.agents/skills` untouched, and reports any entry it cannot move safely.
- `update-repo-skills.sh` now performs a post-sync one-root verification: the legacy root must have no non-system entries and every tracked repo skill must exist on `~/.agents/skills` as a marked copy. README records `C:\Users\<user>\.codex\skills-migrated-20260707-091501` as local evidence for the legacy backup shape, not as a test fixture.
- Added `docs/codex-skill-backup-recovery.md` for inspecting migrated backups, restoring genuine local-only skills to `~/.agents/skills`, avoiding `~/.codex/skills` double-loading, and deciding when backups can be deleted.
- The sync includes marker-scoped orphan cleanup (a skill deleted or renamed in `skills/` also disappears from the Codex surface; unmarked dirs are never touched) and `review-claudemd` was unified into one CLI-agnostic skill (CLAUDE.md/AGENTS.md, `~/.claude`/`~/.codex`), replacing the hand-adapted Codex-only variant that previously required a deny-list entry.
- `update-anthropic-skills.sh` now copies Anthropic's `docx`, `xlsx`, `pdf`, and `pptx` skills to the Codex surface as well as the Claude/repo surface, with a black-box test covering both surfaces and stale owned-copy cleanup.
- Third-party skill updaters now reuse marker-scoped orphan cleanup before regenerating their `.gitignore` blocks, so upstream-removed marked copies disappear instead of becoming trackable directories; empty enumerations still refuse cleanup.
- Review fixes: `nano-banana-pro` example paths moved off the deleted `~/.codex/skills` root to `~/.claude/skills` (Codex note included), and `review-claudemd`'s history-discovery snippet sets a concrete `CLI_DIR` default so the block runs verbatim again.
- New `tests/update-repo-skills-test.sh` black-box suite (issues #2 and #4): scratch-HOME fixtures assert marked copies for tracked skills, tracked-only enumeration, orphan cleanup on delete/rename, unmarked-dir safety, legacy drift migration for root symlinks, directories, symlinks, and pointer files, blocked-migration reporting, idempotence, fail-loud propagation, the no-rsync cp fallback, and empty-tracked-set refusal (a broken enumeration must never mass-delete the Codex surface).

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
