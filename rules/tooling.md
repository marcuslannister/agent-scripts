# Tools and task routing

## Find code

1. If the repository has `.codegraph/`, use CodeGraph before other code searches or reads.
   Use the `codegraph_explore` MCP tool or `codegraph explore "<symbols or question>"`.
   It returns source and call paths. Without `.codegraph/`, skip it. Only the user decides whether to index a repository.
2. Otherwise, locate files with `rg` and `fd`.
3. Read the files found by the search.

Prefer `rg`, `fd`, `sd`, and `eza` over `grep`, `find`, `sed`, and `ls`.
Use a classic tool only when the modern tool cannot do the task safely or exactly.

## Edit files

Use Anvil MCP tools for targeted edits:

- Three or more edits in one file: use `mcp__anvil-emacs-eval__file-batch`. Do not make separate calls for one logical edit.
- Text replacement: use `file-replace-string` or `file-replace-regexp` under the same tool prefix.
- Line edits: use `file-insert-at-line`, `file-delete-lines`, or `file-append` under the same prefix.
- Small one-off changes: built-in `Edit` is also allowed.

Avoid repeated full-file reads and repeated elisp patterns. Use targeted file tools instead.
Run heavy Emacs operations with `mcp__anvil__emacs-eval-async`. Poll with `mcp__anvil__emacs-eval-jobs` and `mcp__anvil__emacs-eval-result`.

Anvil's `org` module is disabled in `~/.emacs.d/lisp/init-local-ai.el`.
It conflicted with interactive Emacs buffers and caused many Syncthing conflict files.
Edit org files with Read/Edit or built-in org tools. Never use Anvil org MCP tools.

Use the `anvil-advanced-ops` skill for worker pools, scheduled tasks, and large output.

## Route work

- Claude Code implementation, refactoring, tests, or fixes: use `$codex-first`.
- Claude Code design, API design, or tiny edits: work directly. In Codex sessions, ignore the Claude Code routing rule.
- Screenshot or live-UI bugs: use `$browser-use`.
- Private or historical questions: search local archives first. For current-state questions, also check that the facts are current.

## Background work in Claude Code

Track each parallel or background job as a separate harness task with `run_in_background: true`.
Label each task for its target. Give each task one sidebar chip.
Never detach lasting work with `&`. Run quick commands in the foreground.
Other harnesses: ignore this section.

## Shell limits

- In zsh, never name a variable `status`.
- In zsh, use an array for a loop over multiple items. A scalar string does not split into words as in bash.
