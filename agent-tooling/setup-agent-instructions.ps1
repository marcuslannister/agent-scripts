# Windows counterpart of setup-agent-instructions.sh.
# Absolute native symlinks: Windows resolves a relative target against the
# path used to open it, so ~/.claude/rules -> ../rules misses when ~/.claude
# is itself a symlink. Sets core.symlinks true globally so Git stops writing
# tracked symlinks as text files.
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$agentsMd = Join-Path $repoRoot 'AGENTS.MD'
$codexMd = Join-Path $repoRoot 'AGENTS.codex.md'
$rulesDir = Join-Path $repoRoot 'rules'
$codexPointer = Join-Path $HOME '.codex\AGENTS.md'
$script:changed = 0

if (-not (Test-Path -LiteralPath $agentsMd)) {
    throw "shared instruction file missing: $agentsMd"
}
if (-not (Test-Path -LiteralPath $codexMd)) {
    throw "generated Codex file missing: $codexMd`nhint: run agent-tooling/build-codex-instructions.sh"
}

function ConvertTo-FullPath([string]$Base, [string]$Target) {
    $Target = $Target -replace '/', '\'
    if ([IO.Path]::IsPathRooted($Target)) {
        return [IO.Path]::GetFullPath($Target).TrimEnd('\')
    }
    return [IO.Path]::GetFullPath((Join-Path $Base $Target)).TrimEnd('\')
}

function Get-PhysicalDir([string]$Dir) {
    $item = Get-Item -LiteralPath $Dir -Force
    if ($item.LinkType) {
        return (ConvertTo-FullPath $item.Parent.FullName (@($item.Target)[0]))
    }
    return $item.FullName.TrimEnd('\')
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    return ((Get-Item -LiteralPath $A).FullName.TrimEnd('\') -ieq (Get-Item -LiteralPath $B).FullName.TrimEnd('\'))
}

function Set-Pointer([string]$Pointer, [string]$Want) {
    $dir = Split-Path $Pointer
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $wantFull = (Get-Item -LiteralPath $Want).FullName.TrimEnd('\')

    if (Test-Path -LiteralPath $Pointer) {
        $item = Get-Item -LiteralPath $Pointer -Force
        if ($item.LinkType) {
            $resolved = ConvertTo-FullPath (Get-PhysicalDir $dir) (@($item.Target)[0])
            if (Test-SamePath $resolved $wantFull) {
                $raw = @($item.Target)[0] -replace '/', '\'
                if ([IO.Path]::IsPathRooted($raw)) { return }
                $item.Delete()
            } else {
                Write-Warning "preserving foreign symlink: $Pointer -> $($item.Target)"
                return
            }
        } else {
            $content = (Get-Content -LiteralPath $Pointer -Raw -ErrorAction SilentlyContinue)
            $rel = if ($content) { $content.Trim() } else { '' }
            $isGitPlaceholder = $rel -and ($rel.IndexOfAny([char[]]"`r`n") -lt 0) -and $rel.Length -lt 200
            if ($Force -or ($isGitPlaceholder -and (Test-SamePath (ConvertTo-FullPath (Get-PhysicalDir $dir) $rel) $wantFull))) {
                Remove-Item -LiteralPath $Pointer -Force
            } else {
                Write-Warning "preserving real file: $Pointer"
                return
            }
        }
    }

    New-Item -ItemType SymbolicLink -Path $Pointer -Target $wantFull | Out-Null
    Write-Output "linked $Pointer -> $wantFull"
    $script:changed++
}

git config --global core.symlinks true

if (Test-Path -LiteralPath $codexPointer) {
    $codexItem = Get-Item -LiteralPath $codexPointer -Force
    if ($codexItem.LinkType) {
        $resolved = ConvertTo-FullPath (Get-PhysicalDir (Split-Path $codexPointer)) (@($codexItem.Target)[0])
        if (Test-SamePath $resolved $agentsMd) {
            $codexItem.Delete()
            Write-Output 'migrated legacy Codex symlink to the generated file'
            $script:changed++
        }
    } elseif (-not $Force) {
        Write-Warning "$codexPointer is a regular file; Codex may be reading stale rules"
        Write-Warning "hint: rerun with -Force to point Codex at $codexMd"
    }
}

# Claude Code
Set-Pointer (Join-Path $HOME '.claude\CLAUDE.md') $agentsMd
Set-Pointer (Join-Path $HOME '.claude\rules') $rulesDir

# Codex (inlined AGENTS.codex.md; no rules dir). -Force replaces a real AGENTS.md.
Set-Pointer $codexPointer $codexMd

# Pi (follows ~/.claude/rules like Claude Code)
Set-Pointer (Join-Path $HOME '.pi\agent\AGENTS.md') $agentsMd

if ($script:changed -eq 0) {
    Write-Output 'instruction pointers up to date'
}
