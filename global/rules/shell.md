# Shell limits and hook details

## zsh

- Never name a variable `status`.
- Use an array for a loop over multiple items. A scalar string does not split into words as in bash.
- Store a command in a function, not a variable: `g() { env -u GITHUB_TOKEN gh "$@"; }`. A variable such as `G="env -u X gh"` does not split into words, so `$G args` fails with `command not found`. Give the function a name that is not an alias in the user's profile: `G() { … }` fails with `defining function based on alias`. Check with `type <name>` first.
- `$EPOCHSECONDS` is empty until `zmodload zsh/datetime`. Use `date +%s` instead.
- Quote every URL or path that contains `?`, such as `gh api 'repos/o/r/contents/f?ref=main'`.

## Tools

- A multi-line `sd -F` can match nothing and still exit 0. A hook blocks a newline inside a quoted `sd` pattern.
- For a `sd` pattern that starts with `-`, put `--` before the pattern: `sd -F -- '-L lisp' '-L user-lisp' file`.
- macOS `/usr/bin/curl` (SecureTransport) has no `--tlsv1.3` and exits 4, so a loop over it reports every host as failed. Test TLS 1.3 with `openssl s_client -tls1_3`, or Python `ssl`. Count the failure types before you trust a result of zero passes.
- `stat` is GNU coreutils here: use `stat -c %y file` for the modification time. `stat -f` prints file system status, not file data.

## ssh

- Over `ssh`, the hook does not check the remote command. If the remote host lacks `rg`, `fd`, `sd`, or `eza`, use `grep`, `find`, `sed`, and `ls` there.
- Write a remote script that uses `grep` or `find` to a file with the file tool, then run `ssh host sh -s < file`. The hook reads these words inside a heredoc body as commands and blocks the whole command.

## Hook details

- The modern-CLI hook blocks `grep` at the start of each command segment (after `;`, `&&`, `||`, or a newline). `grep` after `|` stays allowed. It rewrites a simple `find -name`, `sed -i`, or `ls` (flags `l a A 1 h` and one path) to `fd`, `sd`, or `eza`. Any other `ls` runs as typed. Use a classic tool only when the modern tool cannot do the task safely or exactly.
- The Git-read hook blocks `git status`, `log`, `diff`, `rev-parse`, bare `branch`, and `worktree list` when the command does only Git reads (with `cd` and read-only filters such as `| head` or `| rg`). In a chain that also does other work, such as commit, push, then check, the reads run. Global options such as `-C <path>` or `--no-pager` do not change this.
- The curl hook blocks a URL plus only `-s`, `-S`, `-L`, `-f`, and for HEAD a separate `-I`. Any other curl option, such as `-H`, `-m`, `-o`, or `-w`, keeps curl.

## Anvil org module

Anvil's `org` module is off: `my/anvil-modules` in `~/.emacs.d/user-lisp/init-local-anvil.el` leaves it out. It conflicted with interactive Emacs buffers and caused many Syncthing conflict files.
