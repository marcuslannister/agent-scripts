# Tools and task routing

Read this before you search a codebase, edit a file, or hand work to another agent.

## Find code: CodeGraph, then rg/fd, then read

1. If the repository has a `.codegraph/` directory, use CodeGraph first: `codegraph_explore` as an MCP tool, or `codegraph explore "<symbols or question>"` in the shell. One call returns verbatim line-numbered source plus call paths. If there is no `.codegraph/` directory, skip CodeGraph. Indexing is the user's decision.
2. Otherwise locate with `rg` and `fd`.
3. Read files only after the search names them.

Prefer modern CLI tools: `rg` > `grep`, `fd` > `find`, `sd` > `sed`, `eza` > `ls`. Use a classic tool only when the modern one cannot express the task safely or exactly.

## Edit files: Anvil MCP tools

Anvil tools ship only the delta, batch edits in one round trip, and avoid full-file reads.

- `mcp__anvil-emacs-eval__file-batch` — 3 or more edits to the same file. Always use it. Never send three separate calls for one logical edit.
- `mcp__anvil-emacs-eval__file-replace-string` / `mcp__anvil-emacs-eval__file-replace-regexp` — pinpoint replacement, no full-file read needed.
- `mcp__anvil-emacs-eval__file-insert-at-line` / `mcp__anvil-emacs-eval__file-delete-lines` / `mcp__anvil-emacs-eval__file-append` — line-level operations.
- Built-in `Edit` — small one-off changes only.

Course-correct mid-task if you notice repeated full-file reads of the same file, the same elisp pattern written twice, or a heavy elisp operation blocking the session. Route heavy operations through `mcp__anvil__emacs-eval-async` (poll with `mcp__anvil__emacs-eval-jobs` / `mcp__anvil__emacs-eval-result`).

Anvil's `org` module is disabled (see `~/.emacs.d/lisp/init-local-ai.el`). It raced with interactive Emacs buffers and caused Syncthing sync-conflict storms. Edit org files directly with Read/Edit or the built-in org tools, never with Anvil org MCP tools.

The `anvil-advanced-ops` skill covers worker-pool dispatch, anvil-cron tasks, and shell/context output compression.

## Route work

- Claude Code implementation, refactor, test, or fix: `$codex-first`. Design, API design, or a tiny edit: do it directly. In a Codex session: ignore this rule.
- Screenshot or live-UI bug: `$browser-use`.
- Private or historical questions: search local archives first. A question about the current state also needs a freshness check.

## Background work (Claude Code only)

Every parallel or background job — Codex workers, monitors, long jobs — is its own harness-tracked task with `run_in_background: true`, labeled for its target, one sidebar chip each. Never `&`-detach durable work: it hides the job so only the agent can see it. Quick foreground commands stay inline. Other harnesses: ignore this rule.

## Shell footguns

- zsh: never name a variable `status`.
- zsh: a multi-item loop needs an array. A scalar string does not word-split the way it does in bash.
