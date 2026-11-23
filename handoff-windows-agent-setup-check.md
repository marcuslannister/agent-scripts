# Handoff: a setup check script, written and tested on a Windows PC

For a Codex or Claude Code agent on the Windows PC `nuc`, in a normal desktop session. Written on the Mac on 2026-11-22.

Part 1 writes and tests `global/bin/check-agent-setup.sh`. Part 2 deploys `global/` (ADR-0013) on this PC and uses the script before and after. Do Part 2 only when the user asks for it.

## Shell

The commands are for Git Bash. Claude Code runs its Bash tool in Git Bash. Codex runs PowerShell: put the commands in a `.sh` file and run it with `& "C:\Program Files\Git\bin\bash.exe" <file>`. PowerShell 7 is `C:\Program Files\PowerShell\7\pwsh.exe`.

## State of this PC (read-only check over SSH, 2026-11-22)

- `core.symlinks` is `true` globally and as a local value in `agent-scripts`, `claude-code-settings`, `codex-settings`, and `pi-settings`. The system value is `false`. The global and local values override it.
- Developer Mode is off: the registry value `AllowDevelopmentWithoutDevLicense` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` is not set.
- An SSH session is elevated, and it can make links. A normal desktop session is not elevated. With Developer Mode off, it probably cannot make links. Nobody has tested this. Your session is the first test.
- Pointers: `~/.claude/CLAUDE.md` and `~/.pi/agent/AGENTS.md` link to the old `agent-scripts/AGENTS.MD`. `~/.codex/AGENTS.md` links to the old `agent-scripts/AGENTS.codex.md`. `~/.claude/agent-rules` does not exist. `~/.claude`, `~/.codex`, and `~/.pi` are links to the three settings repos.
- `~/Projects/agent-scripts` is 59 commits behind `origin/main` and has no local commits. It has one untracked file that is not yours (`Enable-OpenSSHServer.ps1`).
- The three settings repos still have the history from before the privacy rewrite, and uncommitted changes. `handoff-windows-privacy-rewrite.md` covers them.
- The privacy guard is off on this PC (step 6 of `handoff-windows-privacy-rewrite.md`). No hook checks your commits.
- Tools: Git Bash, `jq`, `rg`, Python 3.12, PowerShell 7.4. No `rsync`.

## Rules

- Do not pull, reset, or switch branches in `~/Projects/agent-scripts`. A pull deletes the root `AGENTS.MD` and `AGENTS.codex.md`, which the current pointers use. New agent sessions then start without the global rules. Work in a worktree (Part 1, step 1).
- Do not run `git fetch` or `git pull` in the six repos of `handoff-windows-privacy-rewrite.md`. Its step 1 must run before a fetch. A fetch in `agent-scripts` is safe, because its history was not rewritten.
- Never write the Windows user name, or a path under `C:\Users` or `/c/Users`, in a file, a commit message, or a reply. Write `~`.
- Never commit a pointer change made on Windows.
- Commit and push only when the user agrees. Never use `--no-verify`.
- `reset --hard`, `clean`, and `restore` need an explicit request from the user each time.

## Part 1: write and test the check script

1. Make a worktree of the current `main`:

   ```bash
   git -C ~/Projects/agent-scripts fetch origin
   git -C ~/Projects/agent-scripts worktree add ~/Projects/agent-scripts-check -b agent-setup-check origin/main
   ```

   Work only in `~/Projects/agent-scripts-check`. `agent-scripts` tracks 10 links in `hooks/`. If `git status` shows them as changed right after the checkout, this session cannot make links. Do not commit them, and record this as the first result for check 2.
2. Read `CLAUDE.md`, `CONTEXT.md`, `docs/adr/0013-global-rules-and-own-skills-live-in-global.md`, the section "Global rules and skills on a Windows PC (no `home` clone)" in `docs/windows.md`, and `global/tests/install-skills-test.sh` (the test form).
3. Write `global/bin/check-agent-setup.sh` in Bash, with no new dependency. It must run in Git Bash on Windows, on macOS, and on Linux (CI runs on `ubuntu-latest`). It finds the repos under `$HOME/Projects`, so a test can set a temporary `HOME`. The checks, in this order:
   1. **Git makes links.** On Windows, `git config --global core.symlinks` is `true`. On all systems, `git config core.symlinks` is not `false` in each of the four repos. A missing repo fails.
   2. **This session can make a link.** Make one in a new `mktemp -d` folder, check it with `[ -L ]`, then delete the folder. On Windows, set `MSYS=winsymlinks:nativestrict` for the `ln -s`, so that a missing privilege fails and does not make a silent copy. On Windows, also show the Developer Mode state and whether the session is elevated. When Developer Mode is off, warn that only elevated sessions can make links. Facts:
      - `reg.exe query 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' //v AllowDevelopmentWithoutDevLicense` reads the value. `//v` stops the Git Bash path conversion.
      - `net session` exits 0 only in an elevated session.
      - Both programs are in `System32`, which is not on the `PATH` of an SSH login shell.
   3. **The four pointers.** Each pointer is a link, and it reads the same as its source in `~/Projects/agent-scripts/global/`. A text file that holds a path fails.

      | Pointer | Source |
      |---|---|
      | `~/.claude/CLAUDE.md` | `global/AGENTS.md` |
      | `~/.claude/agent-rules` (folder) | `global/rules/` |
      | `~/.codex/AGENTS.md` | `global/AGENTS.codex.md` |
      | `~/.pi/agent/AGENTS.md` | `global/AGENTS.codex.md` |

   4. **The own skills.** For each folder in `global/skills/`, a copy exists in `~/.claude/skills/` and in `~/.agents/skills/`, and it is the same as the source. The fix is `bash global/bin/install-skills.sh`.

   `--preflight` runs checks 1 and 2 only. Use it before a pull, while the pointers still have the old targets. Each check prints one line with `✓` or `✗`. A `✗` line gives the fix in a few words. Print `~` in place of `$HOME`. Exit 0 when all checks pass, and 1 when a check fails.
4. Write `global/tests/check-agent-setup-test.sh` in the form of the other tests in `global/tests/`, with a temporary `HOME` and fixture repos. Cases:
   - All checks pass, and the exit code is 0.
   - A pointer is a text file: `✗`, and the exit code is 1.
   - A pointer links to a wrong file.
   - A skill copy is stale.
   - A repo has `core.symlinks=false`.
   - `--preflight` passes while a pointer is wrong.

   `agent-tooling/verify.sh` runs each `global/tests/*-test.sh`, so CI runs the new test. The fixtures need links. If this session cannot make links, the test cannot run here: say so, and ask the user to run it in an elevated Git Bash. `agent-tooling/verify.sh` is made for macOS and Linux. On Windows, run only the new test.
5. Real run on this PC: run `bash ~/Projects/agent-scripts-check/global/bin/check-agent-setup.sh --preflight`, then the same command without `--preflight`. Before Part 2, the full check fails as expected: the pointers have the old targets, and `~/Projects/agent-scripts` has no `global/` yet. Give both outputs to the user.
6. Docs:
   - In `docs/windows.md`, replace the PowerShell pointer check with the script, and add the `--preflight` run before the pull.
   - In `docs/windows.md` and ADR-0013, replace "Developer Mode on, or an admin account" with "Developer Mode on, or an elevated shell (Run as administrator)". The reason: an admin account in a normal session cannot make links while Developer Mode is off.
   - Add the script where `README.md` lists the `global/bin/` scripts.
   - Add one line to `CHANGELOG.md` under "Unreleased".
7. Commit on `agent-setup-check`: one commit, for example `feat(global): add check-agent-setup.sh`. Add only your own files. The privacy guard is off here, so check the staged change first. Both commands must print nothing:

   ```bash
   git diff --cached | grep -iwF "$USERNAME"
   git diff --cached | grep -inE '/c/Users/|C:\\Users'
   ```

   When the user agrees, push the branch: `git push origin agent-setup-check`. Do not push to `main`. The user reviews and merges the branch.
8. Reply to the user: the commit hash, the test result, the two outputs of step 5, and what you could not test.

## Part 2: deploy `global/` on this PC (only when the user asks)

Do all steps in one sitting, in this order. Between step 2 and step 3, the pointers are broken.

1. Run `bash ~/Projects/agent-scripts-check/global/bin/check-agent-setup.sh --preflight` in the session that does the deploy. If check 2 fails, stop. The user turns on Developer Mode (Settings, System, For developers), or runs the deploy in an elevated shell.
2. Pull `agent-scripts`: `git -C ~/Projects/agent-scripts pull --ff-only`. Keep `Enable-OpenSSHServer.ps1`. This is step 1 of the ADR-0013 pull order.
3. Do `handoff-windows-privacy-rewrite.md` for its six repos. This resets the three settings repos to `origin/main`, and their tracked links then target `agent-scripts/global/`. For its step 1 in `claude-code-settings`, `codex-settings`, and `pi-settings`: one fetch already ran there, so use `git log origin/main@{1}..HEAD`. On 2026-11-22, their `HEAD` was `aa1fc33`, `fceccba`, and `f162b79`, which are the same as `origin/main@{1}`. If `HEAD` did not change, they have no unpushed commits. Save the uncommitted changes before the reset.
4. Run `bash ~/Projects/agent-scripts/agent-tooling/update-local.sh`. It installs the own skills too. All its result lines must show `✓`.
5. Run `bash ~/Projects/agent-scripts-check/global/bin/check-agent-setup.sh`. All checks must pass.
6. Start Claude Code once, and accept the `ponytail@ponytail` and `nowledge-mem@nowledge-community` installs. A new Claude Code session then starts with the short Nowledge note, and its skill list has no `ponytail-gain`, `ponytail-help`, `ponytail-debt`, or `ponytail-audit`.
7. Optional, for Codex only: run `NOWLEDGE_LEAN_CODEX=1 bash ~/Projects/agent-scripts/agent-tooling/nowledge-lean-codex-pi.sh`, then start `codex` and press `t`. The Pi path that the script expects exists here (`~/.pi/agent/npm/node_modules/nowledge-mem-pi/extensions/nowledge-mem.ts`), but nobody has run the script on Windows. If the Pi part fails, tell the user.
8. Start a new agent session. A running session keeps the rules that it loaded when it started. After the branch is pushed and the user agrees, remove the worktree: `git -C ~/Projects/agent-scripts worktree remove ~/Projects/agent-scripts-check`.
9. Reply to the user: the result of each step, and the output of the full check.
