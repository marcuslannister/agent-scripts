# Update the hook repos on a Windows PC

Use this on a Windows PC that has clones of the hook repos. Run it in Git Bash. The prompt to the agent is: "Read `~/Projects/agent-scripts/docs/update-hook-repos-windows.md` and follow it."

Since 2026-11-24, `main` of the three hook repos has the cross-platform fixes (GNU `stat`, CRLF from `jq.exe`, PowerShell commands for Codex, heredoc bodies). CI runs the hook tests on macOS, Ubuntu, and Windows.

## Steps

1. For each repo in `~/Projects/claude-code-settings`, `~/Projects/codex-settings`, and `~/Projects/pi-settings` (skip one that does not exist):
   - Show `git status --short` and `git diff -- hooks/lib.sh`.
   - If the only change in `hooks/lib.sh` is the swap of `/usr/bin/stat -c %Y` before `/usr/bin/stat -f %m`, run `git restore hooks/lib.sh`. `main` already has this fix, and the local edit blocks the pull. Ask the user before you discard any other change.
   - Run `git switch main` and `git pull --ff-only`. Report the HEAD SHA.
2. Run the self-checks and report the passed and failed counts:
   - `bash hooks/test-hooks.sh` in `claude-code-settings` and in `codex-settings`.
   - `node agent/extensions/claude-hooks-guard/test.ts` in `pi-settings`.
3. Run `SSH_CLIENT=x bash -c 'echo ok' | od -c`. If the output has ESC bytes (`033`), `~/.bashrc` prints text in non-interactive shells. Then every hook output is broken, and Claude Code ignores block decisions. Show `~/.bashrc` and propose `[[ $- != *i* ]] && return` as its first line, with a backup. Do not edit it without the user's OK.
4. In `codex-settings`, run `bash hooks/install.sh`. Then tell the user to open Codex and run `/hooks` to trust the hooks. Reason: Codex skips untrusted hooks with no warning.

## Rules

- Do not commit or push.
- At the end, give a short table: repo, HEAD, test counts, and what is left for the user.
