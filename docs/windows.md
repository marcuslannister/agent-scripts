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

The global rules and the own skills are in `global/` (ADR-0013). A PC needs this repo and the three settings repos (`claude-code-settings`, `codex-settings`, `pi-settings`), not `home`.

Prerequisites:
- Git for Windows with symlinks on: `git config --global core.symlinks true`. Set it before you pull the settings repos. Without it, Git writes each tracked link as a text file.
- The symlink privilege: Developer Mode on, or an admin account.
- PowerShell 7 (`pwsh`). Windows PowerShell 5.1 makes absolute link targets, so the setup script refuses it.
- Git Bash, `jq`, and `rg` on PATH (the updaters run in Git Bash), and Python 3 for the lean patches.

Update:
- Pull in this order: `agent-scripts`, then `claude-code-settings`, `codex-settings`, and `pi-settings`, then `home` if the PC has it. `home` goes last, because it deletes the old link targets. `agent-tooling/update-local.sh` pulls `agent-scripts` only.
- The four rule pointers are links that the settings repos track, so a pull of the settings repos sets them. Run `pwsh -File global\bin\setup-agent-instructions.ps1` only where `~/.claude`, `~/.codex`, or `~/.pi` is not the settings repo.
- The own skills are copies. `agent-tooling/update-local.sh` installs them. To install them alone, run `bash global/bin/install-skills.sh` in Git Bash.

Check that the four pointers resolve:
- `Get-Item ~\.claude\CLAUDE.md, ~\.claude\agent-rules, ~\.codex\AGENTS.md, ~\.pi\agent\AGENTS.md | Select-Object FullName, LinkType, Target`: each `LinkType` is `SymbolicLink`, and each `Target` ends in `agent-scripts\global\...`.
- `Get-Content ~\.claude\agent-rules\tooling.md -TotalCount 1` prints a line.

Never commit a pointer change made on Windows. A text file or an absolute target in a commit breaks the other PCs.
