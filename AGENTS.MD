Speak caveman. Telegraph. Noun chunks. Grammar optional. Few tokens.

## Core

- "Make a note" here = terse `AGENTS.MD` edit. No separate `CLAUDE.md`.
- `ship` = changelog, grouped commits, push, pull.
- Version bump only explicit release ask. Release = GitHub Release; also npm publish when package applies.
- Verified release done: bump changelog to next patch `Unreleased`; commit.
- Release verify: docs/notes contain current changelog. Missing/stale: fix before closeout.
- npm release verify: `npm view <pkg>@<version>` proves version, dist-tag, tarball, integrity, publish time. GitHub tag + Release exist. Release body links npm version page, registry tarball, integrity, CI/proof.
- Changelog: match house style; one-line bullet preferred. No prose-length hard-wrap.
- Skills own tool workflows. This file: hard rules only.
- Here/skill edits: token-cheap, loose grammar, terse descriptions.
- Skill description: short generic trigger, not summary. No personal names, long paths, workflow tale unless routing needs it.
- Skill frontmatter: quote `description`. After SKILL.md edit: YAML-parse frontmatter before commit.
- Tool catalog needed: read `~/Projects/agent-scripts/tools.md`.
- Private agent chat + authenticated org-approved systems = internal. Use task-needed non-public names, links, systems, processes, people. Answering authorized user != public disclosure.
- External disclosure: no non-public org info to public audience, external recipient, or unapproved service without explicit approval of both content + destination.
- Secrets: never reveal values, even internal. Approved secret tools; redact output.
- Audience/destination unclear: ask before external send. Confidentiality alone no block on internal research/answers.
- Image/screenshot upload: first verify destination approval. Personal device: user-requested destination okay, external-disclosure rules still apply. Work device: external upload default deny; need explicit content + destination approval for device/data class. Never send possibly confidential/internal image to social media, public image host, or unapproved AI/vision service. Device/sensitivity/approval unclear: stop + ask. Local-only processing okay.
- Personal GitHub repos: push/write as `marcuslannister`
- `manager`, `conferences`, `agent-scripts` = internal ops/note repos. After task change: validate, commit, push, pull/verify, leave clean. No push approval needed.
- Chief of Staff: after each completed action, advance highest-value authorized open loop. Useful work remains: no waiting for "what next?" Prepare blocked steps; ask only exact needed decision.

## Routing

- Claude Code session: implementation/refactor/test/fix defaults `$codex-first` (GPT-5.5+ faster/better code, flat-rate; Claude specs/reviews/verifies). Design/API design/tiny edit: direct. Codex session: ignore.
- Screenshot/assets: newest PNG in `~/Desktop` or `~/Downloads`; verify UI before replace.
- Screenshot/live-UI bug: `$browser-use` with existing Chrome profile. `curl`/source = support only. No Playwright/Puppeteer/in-app browser for login/profile-dependent pages unless asked.
- Private/history: local archives first; current question needs freshness check.

## Project Defaults

- Need upstream file: stage `/tmp/`, cherry-pick. Never overwrite tracked file.
- Bug: regression test when fitting.
- Fix/refactor: delete old path by default. "Shipped" = release Git tag, not main/GitHub/PR. Compat needs named contract: public API/CLI/config/data, tagged upgrade, security boundary, or observed prod state. Unsure: ask before alias/shim/fallback. Tests alone != contract.
- Use repo package manager/runtime. Swap needs approval.
- Docs: read repo docs before code. User-visible behavior change: update docs/changelog.
- Inline comment: brief; only tricky, bug-prone, or formerly buggy logic.
- New dependency: quick health check—recent release, commits, adoption.

## PR / CI

- Broad GitHub reads: shimmed `gh` / `gitcrawl gh` first. Raw `gh api search/* -f ...` needs `--method GET`; gitcrawl shim sanitizes.
- Pasted GitHub issue/PR: first `git status -sb`. Dirty: yell. Then `git push` + `git pull --ff-only`.
- PR refs: `gh pr view/diff`; no web search.
- PR: prefer fix/rewrite PR then merge, not close + duplicate direct commit.
- PR quality: assume generated code may come from weaker AI. Review/improve before land; full rewrite okay when cleaner.
- Explicit land of own draft PR: ignore draft; mark ready if needed; continue.
- `fix ci` = consent to pull, commit, push; fix/rerun/watch until green.
- CI: `gh run list/view`; asked = rerun/fix until green.
- `rewrite commits + land`: clean stack, only agreed focused proof, force-push, merge. No Codex review, PR-body proof polish, CI babysit unless asked.
- Before commit/land code: `$autoreview` until no accepted/actionable finding. Skip only equivalent manual review, trivial/docs-only, or user opt-out.
- Reply: cite fix + file/line. Resolve thread only after fix lands.
- Issue fixed on `main` with proof: comment proof + commit/PR; close.
- User-facing fix/landed PR: changelog unless test/internal only.
- Contributor PR author: no changelog edit. Maintainer/AI adds on merge.
- After land final: 2–5 sentence recap.
- After land: checkout `main`; `git pull --ff-only`; verify `git status -sb`; then final.
- Merge contributor PR: thank contributor in `CHANGELOG.md`.
- Contributor PR unpushable (`maintainerCanModify=false`/no head write) + fixup needed: recreate locally from PR head/diff; one maintainer commit; push; close PR with comment.
- Preserve contributor credit: commit body `Co-authored-by: Name <email>` from PR commit author. Changelog still thanks `@login` for user-visible work.
- PR fixup: use repo cwd. No worktree unless asked. Awkward: ask.
- Close comment: link landed commit; say branch not writable; thank author; suggest future "Allow edits by maintainers".

## Runtime Safety

- zsh: never variable `status`.
- zsh multi-item loop: array. Scalar string does not word-split like bash.
- Public GitHub body: never inline double-quoted text containing backticks, `$`, shell snippet, env name, or user text. Temp file + `cat <<'EOF'` + inspect + `--body-file`.
- PR/issue body edit: REST + `jq -r`; never `gh pr/issue view --json body --jq .body`. Example: `gh api repos/OWNER/REPO/pulls/NUM | jq -r '.body // ""' > /tmp/body.md`; inspect before `--body-file`; stop on leading `"` or literal `\n`.
- Secrets: never normal-shell `env`, `set`, `export -p`, broad secret regex dump. Query exact name only; redact value.
- After secret/env handling, public `gh` write: unset token env where possible: `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN ...`.

## Git

- Cwd inside repo: work there. No sibling checkout unless asked.
- No CLI `git worktree` unless asked. Dirty/wrong branch/awkward: ask.
- Branch switch/checkout okay when task needs and repo rules allow.
- `~/Projects` has intentional same-repo checkouts. User-managed, not scratch.
- Cwd outside repo: freeform; choose sensible folder; say path before edits. Worktree okay if useful.
- Safe default: `git status/diff/log`.
- Push only when user asks.
- End in expected visible checkout/branch.
- Branch change needs user consent.
- Destructive ops forbidden unless explicit: `reset --hard`, `clean`, `restore`, `rm`, etc.
- Commit helper on PATH: `committer` (bash); prefer it. Repo `./scripts/committer` wins.
- Commit style: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Locked Mac / Secretive failure: use HTTPS. Signing-blocked commit: retry `--no-gpg-sign`.
- No repo-wide search/replace scripts. Small reviewable edits.
- User command like "pull and push" = consent for that command.
- No amend unless asked.
- Unknown changes = other agent. Continue, touching own scope. Conflict/problem: stop + ask.

## Running shell commands

- Prefer modern CLI tools: `rg`>`grep`, `fd`>`find`, `sd`>`sed`, `eza`>`ls`. Use classic tools only when the modern one can't express the task safely or exactly.

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

Skill `anvil-advanced-ops` covers org-mode editing, worker-pool
dispatch for heavy Emacs ops, anvil-cron scheduled tasks, and
shell/context output compression.

## MCP tool self-reinforcement

If during a task you notice any of the following, switch to
the appropriate Anvil tool before continuing:

- The same elisp pattern is being written twice in one session
- Three or more `anvil-eval` calls were issued for one logical edit
  (a single `anvil-file-batch` would have sufficed)
- Repeated full-file Reads of the same large file
- A heavy elisp op blocked the main session — should have been
  routed via `anvil-worker-call` / `mcp__anvil-worker__eval`

Course-correct mid-task — do not wait until the end.
