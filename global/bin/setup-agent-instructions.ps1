#Requires -Version 7
# Windows counterpart of setup-agent-instructions.sh.
# Relative native symlinks, the same targets that the Bash setup makes, so a link
# made here equals the link that a settings repo tracks. PowerShell 7 keeps a
# relative target as written; Windows PowerShell 5.1 makes every target absolute,
# and an absolute target puts the Windows user name into the link (ADR-0013).
# The target starts at the physical directory of the link, because ~/.claude and
# ~/.pi are themselves links into the settings repos. Sets core.symlinks true
# globally so Git stops writing tracked symlinks as text files.
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$agentsMd = Join-Path $repoRoot 'AGENTS.md'
$codexMd = Join-Path $repoRoot 'AGENTS.codex.md'
$rulesDir = Join-Path $repoRoot 'rules'
$codexPointer = Join-Path $HOME '.codex\AGENTS.md'
$piPointer = Join-Path $HOME '.pi\agent\AGENTS.md'
$script:changed = 0

if (-not (Test-Path -LiteralPath $agentsMd)) {
    throw "shared instruction file missing: $agentsMd"
}
if (-not (Test-Path -LiteralPath $codexMd)) {
    throw "generated Codex file missing: $codexMd`nhint: run global/bin/build-codex-instructions.sh"
}

function ConvertTo-FullPath([string]$Base, [string]$Target) {
    $Target = $Target -replace '/', '\'
    if ([IO.Path]::IsPathRooted($Target)) {
        return [IO.Path]::GetFullPath($Target).TrimEnd('\')
    }
    return [IO.Path]::GetFullPath((Join-Path $Base $Target)).TrimEnd('\')
}

# Resolve every link on the way, not only the last one: ~/.pi is a link into
# pi-settings, so ~/.pi/agent is physically inside that repo.
function Get-PhysicalPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $cur = $root
    foreach ($part in $full.Substring($root.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries)) {
        $cur = Join-Path $cur $part
        for ($hops = 0; $hops -lt 32 -and (Test-Path -LiteralPath $cur) -and (Get-Item -LiteralPath $cur -Force).LinkType; $hops++) {
            $cur = ConvertTo-FullPath (Split-Path $cur) (@((Get-Item -LiteralPath $cur -Force).Target)[0])
        }
    }
    return $cur.TrimEnd('\')
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    return ((Get-Item -LiteralPath $A).FullName.TrimEnd('\') -ieq (Get-Item -LiteralPath $B).FullName.TrimEnd('\'))
}

function Set-Pointer([string]$Pointer, [string]$Want, [string]$Legacy = '') {
    $migrated = $false
    $dir = Split-Path $Pointer
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $wantFull = (Get-Item -LiteralPath $Want).FullName.TrimEnd('\')
    $wantRel = [IO.Path]::GetRelativePath((Get-PhysicalPath $dir), (Get-PhysicalPath $wantFull))
    if ([IO.Path]::IsPathRooted($wantRel)) {
        Write-Warning "no relative path from $dir to $wantFull (another drive); using the absolute path"
    }

    if (Test-Path -LiteralPath $Pointer) {
        $item = Get-Item -LiteralPath $Pointer -Force
        if ($item.LinkType) {
            $raw = @($item.Target)[0]
            $resolved = ConvertTo-FullPath (Get-PhysicalPath $dir) $raw
            if (Test-SamePath $resolved $wantFull) {
                if (($raw -replace '/', '\') -ieq $wantRel) { return }
                # The same place in another spelling, for example an absolute target
                # from an older setup: replace it with the relative one.
                $item.Delete()
            } elseif ($Legacy -and (Test-SamePath $resolved $Legacy)) {
                # An earlier setup linked this pointer to $Legacy, so it is ours.
                # Replacing it in this step means a failure elsewhere never
                # leaves the pointer missing.
                $item.Delete()
                $migrated = $true
            } else {
                Write-Warning "preserving foreign symlink: $Pointer -> $($item.Target)"
                return
            }
        } else {
            $content = (Get-Content -LiteralPath $Pointer -Raw -ErrorAction SilentlyContinue)
            $rel = if ($content) { $content.Trim() } else { '' }
            $isGitPlaceholder = $rel -and ($rel.IndexOfAny([char[]]"`r`n") -lt 0) -and $rel.Length -lt 200
            if ($Force -or ($isGitPlaceholder -and (Test-SamePath (ConvertTo-FullPath (Get-PhysicalPath $dir) $rel) $wantFull))) {
                Remove-Item -LiteralPath $Pointer -Force
            } else {
                Write-Warning "preserving real file: $Pointer"
                return
            }
        }
    }

    New-Item -ItemType SymbolicLink -Path $Pointer -Target $wantRel | Out-Null
    Write-Output "linked $Pointer -> $wantRel"
    if ($migrated) { Write-Output "migrated legacy symlink $Pointer" }
    $script:changed++
}

git config --global core.symlinks true

# A regular file is never ours to judge, so it is reported and left alone.
if ((Test-Path -LiteralPath $codexPointer) -and -not (Get-Item -LiteralPath $codexPointer -Force).LinkType -and -not $Force) {
    Write-Warning "$codexPointer is a regular file; Codex may be reading stale rules"
    Write-Warning "hint: rerun with -Force to point Codex at $codexMd"
}

# Claude Code
Set-Pointer (Join-Path $HOME '.claude\CLAUDE.md') $agentsMd
# Not ~/.claude/rules: Claude Code loads every file there at startup.
Set-Pointer (Join-Path $HOME '.claude\agent-rules') $rulesDir
$oldRules = Join-Path $HOME '.claude\rules'
if (Test-Path -LiteralPath $oldRules) {
    $oldItem = Get-Item -LiteralPath $oldRules -Force
    if ($oldItem.LinkType -and (Test-SamePath (ConvertTo-FullPath (Get-PhysicalPath (Split-Path $oldRules)) (@($oldItem.Target)[0])) $rulesDir)) {
        $oldItem.Delete()
        Write-Output "removed legacy pointer $oldRules"
        $script:changed++
    }
}

# Codex (inlined AGENTS.codex.md; no rules dir). -Force replaces a real AGENTS.md.
# Since the split, a legacy link to AGENTS.md leaves Codex with only a link list
# it cannot follow. Pi 1.5.2 never expands the @ imports in it either.
Set-Pointer $codexPointer $codexMd $agentsMd
Set-Pointer $piPointer $codexMd $agentsMd

if ($script:changed -eq 0) {
    Write-Output 'instruction pointers up to date'
}
