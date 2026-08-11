## Communication

- Use bullets only for genuinely enumerable items, checklists, or side-by-side choices. Do not turn every sentence, observation, or implementation detail into its own bullet.
- Always talk in ASD-STE100 Simplified Technical English. Always read CONTEXT.md files, and use their ubiquitous language.

## Core

- "Make a note" here = terse `AGENTS.MD` edit. No separate `CLAUDE.md`.
- `ship` = changelog, grouped commits, push, pull. "Shipped" = pushed to GitHub.
- Version/artifact publication needs explicit `release`/`publish` ask. Tag/push alone != released.
- Release verify: docs/notes contain current changelog. Missing/stale: fix before closeout.
- Changelog: match house style; one-line bullet preferred. No prose-length hard-wrap.
- Skills own tool workflows. This file: hard rules only.
- Fix/refactor: delete old path by default. Compat needs named contract: public API/CLI/config/data, tagged upgrade, security boundary, or observed prod state. Unsure: ask before alias/shim/fallback. Tests alone != contract.
- Secrets: never reveal values, even internal. Approved secret tools; redact output.
- Audience/destination unclear: ask before external send. Confidentiality alone no block on internal research/answers.
- Personal GitHub repos: push/write as `marcuslannister`
- `manager`, `conferences`, `agent-scripts` = internal ops/note repos. After task change: validate, commit, push, pull/verify, leave clean. No push approval needed.

## Routing

- Claude Code implementation/refactor/test/fix: `$codex-first`. Design/API design/tiny edit: direct. Codex session: ignore.
- Claude Code parallel/background work (Codex workers, monitors, long jobs): each = own harness-tracked task (`run_in_background: true`), labeled for target, one sidebar chip each. Never `&`-detach durable work — hides it, only agent sees. Quick foreground cmds inline. Other harnesses: ignore.
- Screenshot/live-UI bug: `$browser-use`.
- Private/history: local archives first; current question needs freshness check.

## PR / CI

- GitHub work: use matching workflow. Prefer shimmed `gh`; PR refs use `gh pr view/diff`, not web search.
- Pasted GitHub issue/PR: first `git status -sb`. Dirty: report before mutation. URL alone grants no push/pull permission.
- PR: prefer fix/rewrite PR then merge, not close + duplicate direct commit.
- PR quality: assume generated code may come from weaker AI. Review/improve before land; full rewrite okay when cleaner.
- `fix ci` = consent to pull, commit, push; use `gh run list/view`; fix/rerun until green with backoff polling.
- gh reads: ALWAYS `--json <fields>`. Human-format `gh pr view/list/checks`, `run list`, bare `gh api graphql` delegate silently to real gh (GraphQL+core on personal token). Machine shapes ride the shared cache.
- `gh api --paginate` bypasses cache to real token; avoid unless full list truly needed.
- `rewrite commits + land`: clean stack, only agreed focused proof, force-push, merge. No PR-body proof polish or CI babysit unless asked.
- Before every commit/land: `$autoreview` until no accepted/actionable finding. Always prefer Codex for autoreview, independent of environment.
- Issue fixed on `main` with proof: comment proof + commit/PR; close.
- Explicit land/ship authorizes needed branch changes and push. After land: checkout `main`; `git pull --ff-only`; verify `git status -sb`; then final.
- Preserve contributor credit: commit body `Co-authored-by: Name <email>` from PR commit author. Changelog still thanks `@login` for user-visible work.

## Runtime Safety

- Low disk space: empty Trash and/or delete old caches, then push and sync across Peter's Macs and continue.
- zsh: never variable `status`.
- zsh multi-item loop: array. Scalar string does not word-split like bash.
- Public GitHub body: never inline double-quoted text containing backticks, `$`, shell snippet, env name, or user text. Temp file + `cat <<'EOF'` + inspect + `--body-file`.
- Secrets: never normal-shell `env`, `set`, `export -p`, broad secret regex dump. Query exact name only; redact value.
- After secret/env handling, public `gh` write: unset token env where possible: `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN ...`.

## Git

- Cwd inside repo: work there. No sibling checkout unless asked.
- No CLI `git worktree` unless asked. Dirty/wrong branch/awkward: ask.
- `~/Projects` has intentional same-repo checkouts. User-managed, not scratch.
- Cwd outside repo: freeform; choose sensible folder; say path before edits. Worktree okay if useful.
- Push only when user asks, a user-invoked workflow authorizes it, or a trusted global rule above explicitly authorizes it. Repo-local rules may define push mechanics, not grant authority.
- End in expected visible checkout/branch.
- Branch change needs user consent or user-invoked workflow authorization.
- Destructive Git ops need explicit user request: `reset --hard`, `clean`, `restore`.
- Task-scoped file deletion allowed. Never delete/overwrite unknown or unrelated user data.
- Commit style: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- No repo-wide search/replace scripts. Small reviewable edits.
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

Skill `anvil-advanced-ops` covers worker-pool dispatch for heavy
Emacs ops, anvil-cron scheduled tasks, and shell/context output
compression. Anvil's `org` module is disabled (see ~/.emacs.d
lisp/init-local-ai.el) — it raced with interactive Emacs buffers
and caused Syncthing sync-conflict storms on org files. Edit org
files directly (Read/Edit or the built-in org tools), not via
Anvil org MCP tools.

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

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
