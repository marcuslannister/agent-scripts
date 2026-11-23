# Tools and task routing

## Find code

1. If the repository has `.codegraph/`, use CodeGraph (`codegraph_explore` or `codegraph explore "<symbols or question>"`) before other code searches or reads. Without `.codegraph/`, skip it. Only the user decides whether to index a repository.
2. Otherwise, locate files with `rg` and `fd`, then read the files found.

## Commands

- Use `rg`, `fd`, `sd`, and `eza`, not `grep`, `find`, `sed -i`, or `ls`. Hooks block or rewrite the classic tools. A blocked command does not run at all, including its other segments: fix it, then run the full command again. Details: [shell.md](~/.claude/agent-rules/shell.md).
- Use `sd` only for one-line patterns. For multi-line replacements, use `Edit` or `file-replace-string`.
- Delete files with `trash <path>`. `rm`, `mv`, and `cp` are interactive aliases (`rm -i`, `mv -i`, `cp -av`) and hang when the target exists. To replace a file, use the Write tool or `cat new > target`.

## Git state and HTTP

When Anvil is reachable, a hook blocks commands that only read Git state, and plain `curl` GET or HEAD requests.

- Read Git state with the `mcp__anvil-emacs-eval__` tools (not `mcp__anvil__`): `git-status`, `git-log`, `git-diff-names` or `git-diff-stats`, `git-head-sha`, `git-branch-current`, and `git-worktree-list`. Use one call for each read. `git diff -- <path>` and `git diff --check` stay allowed. For a full commit SHA in a shell command, use `git rev-list -1 HEAD`.
- The hook also blocks these reads in subagents. To give a subagent a diff, write it to a file with `git diff <base>...HEAD -- . > <file>`, and give it the path.
- For a plain GET or HEAD, use `http-fetch` or `http-head` under the same prefix.

## Edit files

- Three or more edits in one file: use `mcp__anvil-emacs-eval__file-batch`. Do not make separate calls for one logical edit.
- Otherwise use `file-replace-string`, `file-replace-regexp`, `file-insert-at-line`, `file-delete-lines`, or `file-append` under the same prefix. Built-in `Edit` is also allowed for small changes.
- Avoid repeated full-file reads and repeated elisp patterns. When you see one of these patterns during a task, change to a targeted tool immediately.
- Never use Anvil org MCP tools. Edit org files with Read and Edit. The reason is in [shell.md](~/.claude/agent-rules/shell.md).
- Run heavy Emacs operations with `mcp__anvil__emacs-eval-async`, and poll with `emacs-eval-jobs` and `emacs-eval-result`. For worker pools, scheduled tasks, and large output, use the `anvil-advanced-ops` skill.

## Route work

- Web research or reading a web page: read [web.md](~/.claude/agent-rules/web.md) first.
- Private or historical questions: search local archives first. For current-state questions, also check that the facts are current.
- When a subagent or delegated worker reports back, check its evidence before you accept it.
- In Claude Code, run each parallel or lasting job as a separate harness task with `run_in_background: true`, one task for each target. Never detach lasting work with `&`. Run quick commands in the foreground.
