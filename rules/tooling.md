# Tools and task routing

## Find code

1. If the repository has `.codegraph/`, use CodeGraph before other code searches or reads.
   Use the `codegraph_explore` MCP tool or `codegraph explore "<symbols or question>"`.
   It returns source and call paths. Without `.codegraph/`, skip it. Only the user decides whether to index a repository.
2. Otherwise, locate files with `rg` and `fd`.
3. Read the files found by the search.

Use `rg`, `fd`, `sd`, and `eza`. A hook blocks `grep` and `ls` at the start of each command segment (after `;`, `&&`, `||`, or a newline); `grep` after `|` stays allowed. It rewrites a simple `find -name` or `sed -i` to `fd` or `sd`.
A blocked command does not run at all, including its other segments. Fix the blocked segment, then run the full command again.
Use a classic tool only when the modern tool cannot do the task safely or exactly.
Over `ssh`, the hook does not check the remote command. If the remote host lacks `rg`, `fd`, `sd`, or `eza`, use `grep`, `find`, `sed`, and `ls` there.

## Read Git state

When Anvil is reachable, a hook blocks read-only `git status`, `log`, `diff`, `rev-parse`, bare `branch`, and `worktree list`. Global options such as `-C <path>` or `--no-pager` do not change this. `git diff --check` and `git diff -- <path>` (file content; `git diff -- .` for the full diff) stay allowed.
Use the `mcp__anvil-emacs-eval__` tools instead (the `git-*`, `file-*`, and `http-*` tools live under this prefix, not `mcp__anvil__`): `git-status`, `git-log`, `git-diff-names` or `git-diff-stats`, `git-head-sha`, `git-branch-current`, and `git-worktree-list`.
For a full commit SHA in a shell command, use `git rev-list -1 HEAD`.
When Anvil is reachable, the hook also blocks a plain `curl` GET or HEAD: a URL plus only `-s`, `-S`, `-L`, `-f`, and for HEAD a separate `-I`. Use `http-fetch` or `http-head` under the same prefix. Any other curl option, such as `-H`, `-m`, `-o`, or `-w`, keeps curl.

## Edit files

Use Anvil MCP tools for targeted edits:

- Three or more edits in one file: use `mcp__anvil-emacs-eval__file-batch`. Do not make separate calls for one logical edit.
- Text replacement: use `file-replace-string` or `file-replace-regexp` under the same tool prefix.
- Line edits: use `file-insert-at-line`, `file-delete-lines`, or `file-append` under the same prefix.
- Small one-off changes: built-in `Edit` is also allowed.
- Delete files: use `trash <path>`. It moves them to the Trash. `rm` asks for confirmation, and `rm -rf` is denied.

Avoid repeated full-file reads and repeated elisp patterns. Use targeted file tools instead.
Run heavy Emacs operations with `mcp__anvil__emacs-eval-async`. Poll with `mcp__anvil__emacs-eval-jobs` and `mcp__anvil__emacs-eval-result`.

Anvil's `org` module is disabled in `~/.emacs.d/lisp/init-local-ai.el`.
It conflicted with interactive Emacs buffers and caused many Syncthing conflict files.
Edit org files with Read/Edit or built-in org tools. Never use Anvil org MCP tools.

Use the `anvil-advanced-ops` skill for worker pools, scheduled tasks, and large output.

## Route work

- Screenshot or live-UI bugs: use `$browser-use`.
- Private or historical questions: search local archives first. For current-state questions, also check that the facts are current.
- When a subagent or delegated worker reports back, check its evidence before you accept it.

## Background work in Claude Code

Track each parallel or background job as a separate harness task with `run_in_background: true`.
Label each task for its target. Give each task one sidebar chip.
Never detach lasting work with `&`. Run quick commands in the foreground.
Other harnesses: ignore this section.

## Shell limits

- In zsh, never name a variable `status`.
- In zsh, use an array for a loop over multiple items. A scalar string does not split into words as in bash.
- In zsh, `noclobber` is on: overwrite an existing file with `>|`. A plain `>` fails with "file exists", and the next command can read stale output.
- In zsh, `noclobber` also blocks `>>` to a file that does not exist. Create the file with `>|`.
- In zsh, `$EPOCHSECONDS` is empty until `zmodload zsh/datetime`. Use `date +%s` instead.
