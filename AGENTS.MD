Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

Personal global rules. Apply to every task unless explicitly overridden. Bias: caution over speed on non-trivial work; use judgment on trivial tasks. Skills are canonical for tool workflows — keep this file to hard rules only.

## Always-on principles

- **Think before coding** — State assumptions explicitly. If uncertain, ask rather than guess. Present multiple interpretations when ambiguity exists. Push back when a simpler approach exists. Stop when confused; name what's unclear.
- **Goal-driven execution** — Define success criteria, loop until verified. Don't follow steps blindly; define success and iterate. Strong criteria let you loop independently.
- **Token budgets are not advisory** — Per-task: 4,000 tokens. Per-session: 30,000. If approaching budget, summarize and start fresh. Surface the breach; don't silently overrun.
- **Surface conflicts, don't average them** — If two patterns contradict, pick one (more recent / more tested), explain why, flag the other for cleanup. Don't blend.
- **Checkpoint after every significant step** — Summarize what was done, verified, left. Don't continue from a state you can't describe back. If you lose track, stop and restate.
- **Fail loud** — "Completed" is wrong if anything was skipped silently. "Tests pass" is wrong if any were skipped. Surface uncertainty, don't hide it.

## Writing, fixing, or modifying code

- **Simplicity first** — Minimum code that solves the problem. Nothing speculative. No features beyond what was asked. No abstractions for single-use code. Would a senior engineer call this overcomplicated? If yes, simplify.
- **Surgical changes** — Touch only what you must. Clean up only your own mess. Don't "improve" adjacent code, comments, or formatting. Don't refactor what isn't broken. Match existing style.
- **Read before you write** — Before adding code, read exports, immediate callers, shared utilities. "Looks orthogonal" is dangerous. If unsure why code is structured a way, ask.
- **Match the codebase's conventions, even if you disagree** — Conformance > taste inside the codebase. If a convention is genuinely harmful, surface it; don't fork silently.
- **Use the model only for judgment calls** — Use me for classification, drafting, summarization, extraction. NOT for routing, retries, deterministic transforms. If code can answer, code answers.
- Bugs: add regression test when it fits.
- Inline code comments: brief notes for tricky, bug-prone, or previously buggy logic.
- Use repo package manager/runtime; no swaps without approval.
- New deps: quick health check for recent releases/commits/adoption.
- Need upstream file: stage in `/tmp/`, then cherry-pick; never overwrite tracked files.
- Read repo docs before coding; update docs/changelog for user-visible behavior changes.
- Fixes/refactors: delete old paths by default. "Shipped" = in a release Git tag, not main/GitHub/PR. Compat needs explicit contract: public API/CLI/config/data, tagged upgrade path, security boundary, or observed prod state. If unsure, ask before keeping aliases/shims/fallbacks. Tests alone are not contracts.

## Writing or modifying tests

- Tests verify intent, not just behavior — encode WHY behavior matters, not just WHAT it does. A test that can't fail when business logic changes is wrong.

## Locating the workspace, cloning repos, or finding OSS code

- Workspace: `~/Projects`. 3rd-party/OSS: `~/Projects/oss`.
- Read `~/Projects/agent-scripts/tools.md` when the tool catalog matters.

## Editing this file or a skill ("make a note")

- "Make a note" => terse `AGENTS.MD` edit. No separate `CLAUDE.md`.
- Editing here/skills: token-efficient, relaxed grammar, terse descriptions.
- Skill descriptions: short generic trigger phrase, not summary; no personal names, long paths, or workflow narration unless needed for routing.
- Skill frontmatter: quote `description`; after SKILL.md edits, YAML-parse frontmatter before commit.

## Shipping, releasing, version bumps, changelogs

- `ship` => changelog, commit in groups, push, pull.
- Version bumps only on explicit release request. Release = GitHub Release; npm publish too when package applies.
- Release closeout: after verified release, bump changelog to next patch `Unreleased`, commit.
- Release verify: confirm release docs/notes contain changelog; if missing/stale, fix before closeout.
- npm release verify: `npm view <pkg>@<version>` shows version, dist-tag, tarball, integrity, publish time; GitHub tag + Release exist; Release body links npm version page, registry tarball, integrity, CI/proof.
- Changelogs: match file style; prefer one bullet per entry on one line. Do not hard-wrap changelog bullets just because prose is long.

## Screenshots, assets, or verifying a live/UI bug

- Screenshots/assets: newest PNG in `~/Desktop` or `~/Downloads`; verify UI before replacing.
- Screenshot/live UI bugs: verify with `$browser-use` against the existing Chrome profile. `curl`/source proof is supporting only; no Playwright/Puppeteer/in-app browser for login/profile-dependent pages unless explicitly requested.

## Private data or history questions

- Local archives first; verify freshness for current questions.

## Secrets, API keys, credentials, test/deploy accounts

- Never run `env`, `set`, `export -p`, or broad secret regex dumps in a normal shell. Query exact names only; redact values.
- After touching secrets/env, public `gh` writes unset token env where possible: `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN ...`.

## Pull requests, issues, CI

- GitHub broad reads: prefer shimmed `gh` / `gitcrawl gh` first. Raw `gh api search/* -f ...` needs `--method GET`; gitcrawl shim sanitizes this.
- Pasted GitHub issue/PR: first `git status -sb`; if dirty, yell; then `git push` + `git pull --ff-only`.
- PR refs: use `gh pr view/diff`, not web search.
- PRs: prefer rewriting/fixing the PR, then merging it, over closing and committing equivalent files directly.
- Landing own draft PR after explicit land request: ignore draft status; mark ready if needed and continue.
- `fix ci`: consent to pull, commit, push; fix/rerun/watch until CI green.
- CI: `gh run list/view`; rerun/fix until green when asked.
- `rewrite commits + land`: clean stack, agreed focused proof only, force-push, merge. No Codex review, PR-body proof polish, or CI babysitting unless asked.
- Pre-land/pre-commit code changes: use `$autoreview` until no accepted/actionable findings remain, unless equivalent manual review already done, trivial/docs-only, or user opts out.
- Replies: cite fix + file/line; resolve threads only after fix lands.
- Issue fixed on `main` with proof: comment proof + commit/PR, then close.
- User-facing fixes/landed PRs: changelog unless pure test/internal.
- Contributor PR authors should not edit changelog; maintainer/AI adds entry at merge.
- After landing: final includes 2-5 sentence recap of what landed.
- After landing: checkout `main`, pull `--ff-only`, verify `git status -sb`, then final.
- When merging contributor PRs: thank contributor in `CHANGELOG.md`.
- Unpushable contributor PRs (`maintainerCanModify=false`/no head write): if fixups needed, recreate locally from PR head/diff, make one maintainer commit, push it, then close PR with comment.
- Preserve contributor credit: commit body includes `Co-authored-by: Name <email>` from PR commit author; changelog still thanks `@login` when user-facing.
- PR fixups from repo cwd: use that checkout. No worktrees unless asked; if awkward, ask.
- Close comment: link landed commit, explain PR branch could not be updated, thank author, suggest enabling "Allow edits by maintainers" for future PRs.

## Editing a GitHub PR/issue body or posting public GitHub text

- Public GitHub bodies: never inline double-quoted text with backticks, `$`, shell snippets, env names, or user text. Use temp file + `cat <<'EOF'` + inspect + `--body-file`.
- PR/issue body edits: fetch via REST + `jq -r`, never `gh pr/issue view --json body --jq .body`. Example: `gh api repos/OWNER/REPO/pulls/NUM | jq -r '.body // ""' > /tmp/body.md`; inspect before `--body-file`; stop if it starts with `"` or shows literal `\n`.

## Git operations

- If cwd is in a git repo: work there. Do not jump to sibling checkout unless asked.
- No `git worktree` from CLI sessions unless user asks. If dirty/wrong branch/awkward: ask.
- Branch switch/checkout ok when task needs it and repo rules allow; branch changes require user consent.
- `~/Projects` has many intentional same-repo checkouts. Treat as user-managed, not scratch.
- If cwd is not a git repo: freeform; pick sensible folder, say path before edits. Worktrees ok if useful.
- Safe by default: `git status/diff/log`. Push only when user asks. No amend unless asked.
- End in visible checkout/branch user expects.
- Destructive ops forbidden unless explicit: `reset --hard`, `clean`, `restore`, `rm`, etc.
- Commit helper on PATH: `committer` (bash). Prefer it; if repo has `./scripts/committer`, use that.
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- No repo-wide S/R scripts; keep edits small/reviewable.
- If user types a command ("pull and push"), that's consent for that command.
- Unrecognized changes: assume other agent; keep going; focus your changes. If it causes issues, stop + ask user.

## Running shell commands

- Prefer modern CLI tools: `rg`>`grep`, `fd`>`find`, `sd`>`sed`, `eza`>`ls`. Use classic tools only when the modern one can't express the task safely or exactly.
- zsh: don't use `status` as a variable.

## File editing

Prefer Anvil MCP tools over the built-in Read/Edit/Write
whenever they apply. They ship only the delta, batch multiple
edits in one round trip, and avoid full-file reads.

- `anvil-file-batch` — 3+ edits to the same file (collapse into one call)
- `anvil-file-replace-string` / `anvil-file-replace-regexp` —
  pinpoint replacement; no need to read the whole file first
- `anvil-file-insert-at-line` / `anvil-file-delete-lines` /
  `anvil-file-append` — localized line-level operations

Use the built-in `Edit` only for small one-off changes. For 3 or
more edits to the same file, always use `anvil-file-batch`.

## org-mode

For section moves, refile, splits, or reading a single heading
from a large org file, use `anvil-org-*` tools instead of
Read+Write. They are 10–20× cheaper in tokens.

- `anvil-org-read-headline` — read a single subtree
- `anvil-org-read-outline` — outline view without bodies
- `anvil-org-edit-body` / `anvil-org-rename-headline` /
  `anvil-org-update-todo-state` — targeted org edits

## Heavy operations — worker dispatch

Long-running Emacs ops (large tangles, byte-compile, multi-MB
org scans, full-tree searches) must not run on the main daemon —
they block every other tool call. Dispatch them through the
worker pool instead.

- Elisp called from inside Anvil: prefer `anvil-worker-call` over
  raw `eval` for anything that may exceed ~1s.
- If the worker is registered as its own MCP server (see README
  "Optional: register the worker pool too"), heavy `eval` calls
  should target `mcp__anvil-worker__eval` directly so the main
  session stays responsive.

Symptom that you should have used the worker: the main MCP
session stops accepting tool calls for several seconds.

## Scheduled tasks (cron)

If `anvil-cron` tasks are configured (lint, health checks, batch
indexers, etc.), do not re-implement their work ad hoc. Inspect
and trigger them through the cron MCP tools:

- `anvil-cron-list` — what tasks exist and their schedules
- `anvil-cron-status` — last run time, status, recent failures
- `anvil-cron-run` — fire a registered task on demand

Before writing a new ad-hoc script, check `anvil-cron-list` —
the job may already be defined.

## Context and output compression

When command output or retrieved context is long, compress it before
feeding it back into the main reasoning loop.

- Use `shell-run` for shell commands whose stdout can be filtered
  automatically. It returns compressed stdout plus a `tee-id`; recover
  the raw output with `shell-tee-get` only when the compressed view is
  insufficient.
- Use `context-compress` for non-shell text: API JSON, RAG snippets,
  web/article extracts, logs from another tool, diffs, or code
  excerpts. Set `store=true` when the raw text may be needed later;
  recover it with `context-retrieve` and the returned `ccr-id`.
- Use `context-stats` / `shell-gain` to inspect savings instead of
  guessing whether the compression layer is helping.

Do not use compressed views as the only source of truth for legal,
financial, safety-critical, or exact numeric work. Retrieve the raw
context before making claims that depend on exact wording or values.
