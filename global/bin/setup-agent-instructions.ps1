#Requires -Version 7.1
# Windows counterpart of setup-agent-instructions.sh.
# Relative native symlinks, the same targets that the Bash setup makes, so a link
# made here equals the link that a settings repo tracks. PowerShell 7.1 or newer
# keeps a relative target as written (and links a relative directory target);
# Windows PowerShell 5.1 makes every target absolute, and an absolute target puts
# the Windows user name into the link (ADR-0013). The target starts at the
# physical directory of the link, because ~/.claude and ~/.pi are themselves links
# into the settings repos. A pointer with no relative target (another drive) stops
# the setup before any change. Sets core.symlinks true globally so Git stops
# writing tracked symlinks as text files.
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
# pi-settings, so ~/.pi/agent is physically inside that repo. A link target can
# hold links too, so each substitution restarts from the first part of the new path.
function Get-PhysicalPath([string]$Path) {
    $walk = [IO.Path]::GetFullPath($Path)
    for ($hops = 0; $hops -lt 40; $hops++) {
        $root = [IO.Path]::GetPathRoot($walk)
        $parts = @($walk.Substring($root.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries))
        $cur = $root
        $next = $null
        for ($i = 0; $i -lt $parts.Count -and $null -eq $next; $i++) {
            $cur = Join-Path $cur $parts[$i]
            if (-not (Test-Path -LiteralPath $cur)) { continue }
            $item = Get-Item -LiteralPath $cur -Force
            if (-not $item.LinkType) { continue }
            $next = ConvertTo-FullPath (Split-Path $cur) (@($item.Target)[0])
            if ($i + 1 -lt $parts.Count) {
                $next = Join-Path $next ($parts[($i + 1)..($parts.Count - 1)] -join '\')
            }
        }
        if ($null -eq $next) { return $walk.TrimEnd('\') }
        $walk = [IO.Path]::GetFullPath($next)
    }
    throw "too many links while resolving $Path"
}

# The relative target of a pointer, from the physical directory of the link, or
# $null where there is none (another drive).
function Get-RelativeTarget([string]$Pointer, [string]$Want) {
    $rel = [IO.Path]::GetRelativePath((Get-PhysicalPath (Split-Path $Pointer)), (Get-PhysicalPath $Want))
    if ([IO.Path]::IsPathRooted($rel)) { return $null }
    return $rel
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
    $wantRel = Get-RelativeTarget $Pointer $Want
    if (-not $wantRel) { throw "no relative target from $dir to $wantFull" }

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

# A pointer needs a relative target: an absolute one puts the Windows user name into
# a link that a settings repo tracks. Check all four before any change, so a refusal
# leaves every pointer as it was.
$claudePointer = Join-Path $HOME '.claude\CLAUDE.md'
$claudeRulesPointer = Join-Path $HOME '.claude\agent-rules'
$noRelative = @()
foreach ($pair in @(@($claudePointer, $agentsMd), @($claudeRulesPointer, $rulesDir), @($codexPointer, $codexMd), @($piPointer, $codexMd))) {
    if (-not (Get-RelativeTarget $pair[0] $pair[1])) { $noRelative += "$($pair[0]) -> $($pair[1])" }
}
if ($noRelative.Count) {
    throw "no relative target for: $($noRelative -join '; '). Keep your home folder and agent-scripts on one drive. No pointer was changed."
}

git config --global core.symlinks true

# A regular file is never ours to judge, so it is reported and left alone.
if ((Test-Path -LiteralPath $codexPointer) -and -not (Get-Item -LiteralPath $codexPointer -Force).LinkType -and -not $Force) {
    Write-Warning "$codexPointer is a regular file; Codex may be reading stale rules"
    Write-Warning "hint: rerun with -Force to point Codex at $codexMd"
}

# Claude Code
Set-Pointer $claudePointer $agentsMd
# Not ~/.claude/rules: Claude Code loads every file there at startup.
Set-Pointer $claudeRulesPointer $rulesDir
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
