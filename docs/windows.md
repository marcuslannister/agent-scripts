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
- PowerShell 7.1 or newer (`pwsh`). Windows PowerShell 5.1 makes absolute link targets, and 7.0 cannot make a relative link to a folder, so the setup script refuses both.
- Git Bash, `jq`, and `rg` on PATH (the updaters run in Git Bash), and Python 3 for the lean patches.

Update:
- Pull in this order: `agent-scripts`, then `claude-code-settings`, `codex-settings`, and `pi-settings`, then `home` if the PC has it. `home` goes last, because it deletes the old link targets. `agent-tooling/update-local.sh` pulls `agent-scripts` only.
- The four rule pointers are links that the settings repos track, so a pull of the settings repos sets them. Run `pwsh -File global\bin\setup-agent-instructions.ps1` only where `~/.claude`, `~/.codex`, or `~/.pi` is not the settings repo.
- The own skills are copies. `agent-tooling/update-local.sh` installs them. To install them alone, run `bash global/bin/install-skills.sh` in Git Bash.

Check that the four pointers resolve. Run this in `pwsh`, in the `agent-scripts` folder. It checks that each pointer is a link, reads each one through its link, and stops on the first error. A copy of a file fails the link check, and a text file fails the comparison:

```powershell
$ErrorActionPreference = 'Stop'
foreach ($p in '.claude\CLAUDE.md', '.claude\agent-rules', '.codex\AGENTS.md', '.pi\agent\AGENTS.md') {
    if ((Get-Item "$HOME\$p" -Force).LinkType -ne 'SymbolicLink') { throw "$p is not a symbolic link" }
}
$reads = @{ '.claude\CLAUDE.md' = 'AGENTS.md'; '.claude\agent-rules\tooling.md' = 'rules\tooling.md'; '.codex\AGENTS.md' = 'AGENTS.codex.md'; '.pi\agent\AGENTS.md' = 'AGENTS.codex.md' }
foreach ($p in $reads.Keys) { if ((Get-Content -Raw "$HOME\$p") -ne (Get-Content -Raw "global\$($reads[$p])")) { throw "$p differs from global\$($reads[$p])" } }
'the four pointers are links and read correctly'
```

Never commit a pointer change made on Windows. A text file or an absolute target in a commit breaks the other PCs.
