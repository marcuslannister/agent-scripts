---
summary: "Windows setup notes for running agent scripts"
read_when:
  - Working on Windows or PowerShell setups for agent scripts.
---

# Windows notes

- Install Git for Windows and ensure git is on PATH.
- Install Node.js 22.18 or newer and ensure `node` is on PATH.
- Run TypeScript helpers explicitly through Node.js from PowerShell, for example `node scripts/docs-list.ts`.

## Global rules and skills on a Windows PC (no `home` clone)

The global rules are in `global/` (ADR-0013), and the own skills are in `other-skills/marcus/` (ADR-0014). A PC needs this repo and the three settings repos (`claude-code-settings`, `codex-settings`, `pi-settings`), not `home`.

Prerequisites:
- Git for Windows with symlinks on: `git config --global core.symlinks true`. Set it before you pull the settings repos. Without it, Git writes each tracked link as a text file.
- The symlink privilege: Developer Mode on, or an elevated shell (Run as administrator). An admin account in a normal session cannot make links while Developer Mode is off.
- PowerShell 7.1 or newer (`pwsh`). Windows PowerShell 5.1 makes absolute link targets, and 7.0 cannot make a relative link to a folder, so the setup script refuses both.
- Git Bash, `jq`, and `rg` on PATH (the updaters run in Git Bash), and Python 3 for the lean patches.
- An SSH login shell (Git Bash over SSH) has a minimal `PATH`. The updaters add `~/.local/bin` when `claude.exe` is there, and never run `install.sh` on Windows. If `claude` is missing, install it from PowerShell: `irm https://claude.ai/install.ps1 | iex`.

Update:
- Before the pull, run `bash global/bin/check-agent-setup.sh --preflight` in Git Bash. It checks Git link support and the current session's link privilege. Continue only when both checks pass. If this checkout has no `global/` yet, run the script from a current worktree, as in `handoff-windows-agent-setup-check.md`.
- Pull in this order: `agent-scripts`, then `claude-code-settings`, `codex-settings`, and `pi-settings`, then `home` if the PC has it. `home` goes last, because it deletes the old link targets. `agent-tooling/update-local.sh` pulls `agent-scripts` only.
- The four rule pointers are links that the settings repos track, so a pull of the settings repos sets them. Run `pwsh -File global\bin\setup-agent-instructions.ps1` only where `~/.claude`, `~/.codex`, or `~/.pi` is not the settings repo.
- The own skills are matrix-selected copies. `agent-tooling/update-local.sh` distributes them.

After the update, run this in Git Bash, in the `agent-scripts` folder. It checks Git link support, the current session's link privilege, and the four instruction pointers. Each check prints one result line. Exit code 1 means that a check failed. A text pointer fails even if it holds the correct path:

```bash
bash global/bin/check-agent-setup.sh
```

Never commit a pointer change made on Windows. A text file or an absolute target in a commit breaks the other PCs.
