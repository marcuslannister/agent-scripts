# Windows counterpart of setup-agent-instructions-test.sh.
# Covers the .ps1 public contract only: absolute links, placeholders, -Force.
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('setup-instr-' + [guid]::NewGuid().ToString('n'))
$fixture = Join-Path $tmp 'repo'
$homeDir = Join-Path $tmp 'home'
$gitConfig = Join-Path $tmp 'gitconfig'
$setupPs1 = Join-Path $fixture 'agent-tooling\setup-agent-instructions.ps1'
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

function Assert-True([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw $Msg }
}

function Get-LinkTarget([string]$Path) {
    return @((Get-Item -LiteralPath $Path -Force).Target)[0]
}

function Test-AbsLink([string]$Pointer, [string]$Want) {
    $item = Get-Item -LiteralPath $Pointer -Force
    Assert-True ($item.LinkType -eq 'SymbolicLink') "not a symlink: $Pointer"
    $raw = Get-LinkTarget $Pointer
    Assert-True ([IO.Path]::IsPathRooted($raw)) "expected absolute symlink: $Pointer -> $raw"
    $got = [IO.Path]::GetFullPath($raw).TrimEnd('\')
    $exp = (Get-Item -LiteralPath $Want).FullName.TrimEnd('\')
    Assert-True ($got -ieq $exp) "target mismatch: $Pointer -> $got (want $exp)"
}

function Invoke-Setup {
    param([switch]$Force)
    $argList = @('-NoProfile', '-NonInteractive', '-File', $setupPs1)
    if ($Force) { $argList += '-Force' }
    $prev = @{
        HOME              = $env:HOME
        USERPROFILE       = $env:USERPROFILE
        GIT_CONFIG_GLOBAL = $env:GIT_CONFIG_GLOBAL
    }
    try {
        $env:HOME = $homeDir
        $env:USERPROFILE = $homeDir
        $env:GIT_CONFIG_GLOBAL = $gitConfig
        $text = & $shell @argList 2>&1 | ForEach-Object { "$_" }
        return @{ Code = $LASTEXITCODE; Text = ($text -join "`n") }
    } finally {
        $env:HOME = $prev.HOME
        $env:USERPROFILE = $prev.USERPROFILE
        $env:GIT_CONFIG_GLOBAL = $prev.GIT_CONFIG_GLOBAL
    }
}

New-Item -ItemType Directory -Path (Join-Path $fixture 'agent-tooling') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fixture 'rules') | Out-Null
New-Item -ItemType Directory -Path $homeDir | Out-Null
New-Item -ItemType File -Path $gitConfig | Out-Null
Copy-Item (Join-Path $RepoRoot 'agent-tooling\setup-agent-instructions.ps1') $setupPs1
Set-Content -LiteralPath (Join-Path $fixture 'AGENTS.MD') "shared rules`n"
Set-Content -LiteralPath (Join-Path $fixture 'rules\topic.md') "topic rules`n"
$agentsMd = Join-Path $fixture 'AGENTS.MD'
$codexMd = Join-Path $fixture 'AGENTS.codex.md'
$rulesDir = Join-Path $fixture 'rules'
$claudeMd = Join-Path $homeDir '.claude\CLAUDE.md'
$claudeRules = Join-Path $homeDir '.claude\rules'
$piMd = Join-Path $homeDir '.pi\agent\AGENTS.md'
$codexPointer = Join-Path $homeDir '.codex\AGENTS.md'

try {
    $r = Invoke-Setup
    Assert-True ($r.Code -ne 0) 'expected setup to fail without AGENTS.codex.md'

    Set-Content -LiteralPath $codexMd "generated`n"

    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "first setup failed: $($r.Text)"
    Test-AbsLink $claudeMd $agentsMd
    Test-AbsLink $claudeRules $rulesDir
    Test-AbsLink $piMd $agentsMd
    Test-AbsLink $codexPointer $codexMd
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $homeDir '.claude\AGENTS.md'))) 'setup must not create ~/.claude/AGENTS.md'
    Assert-True ($r.Text -match 'linked ') "expected linked output: $($r.Text)"

    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "second setup failed: $($r.Text)"
    Assert-True ($r.Text -match 'instruction pointers up to date') "expected up to date: $($r.Text)"

    # Real file and foreign symlink are preserved without -Force.
    Remove-Item -LiteralPath $claudeMd -Force
    Set-Content -LiteralPath $claudeMd "user rules`n"
    Remove-Item -LiteralPath $codexPointer -Force
    $foreign = Join-Path $homeDir 'custom-codex.md'
    Set-Content -LiteralPath $foreign "user codex rules`n"
    New-Item -ItemType SymbolicLink -Path $codexPointer -Target $foreign | Out-Null
    $r = Invoke-Setup
    Assert-True ((Get-Content -LiteralPath $claudeMd -Raw).Trim() -eq 'user rules') 'real file was replaced'
    Assert-True ((Get-LinkTarget $codexPointer) -ieq $foreign) 'foreign symlink was replaced'
    Assert-True ($r.Text -match 'preserving real file') "expected preserve real file: $($r.Text)"
    Assert-True ($r.Text -match 'preserving foreign symlink') "expected preserve foreign: $($r.Text)"

    # -Force replaces a regular file at a pointer path.
    $r = Invoke-Setup -Force
    Assert-True ($r.Code -eq 0) "-Force setup failed: $($r.Text)"
    Test-AbsLink $claudeMd $agentsMd

    # A relative symlink to the same place is rewritten as absolute.
    Remove-Item -LiteralPath $claudeRules -Force
    New-Item -ItemType SymbolicLink -Path $claudeRules -Target '..\..\repo\rules' | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "relative rewrite failed: $($r.Text)"
    Assert-True ($r.Text -notmatch [regex]::Escape("preserving foreign symlink: $claudeRules")) 'equivalent relative symlink treated as foreign'
    Test-AbsLink $claudeRules $rulesDir

    # Git-for-Windows placeholder: a one-line relative path file.
    Remove-Item -LiteralPath $claudeMd -Force
    $rel = [IO.Path]::GetFullPath((Join-Path (Split-Path $claudeMd) '..\..\repo\AGENTS.MD'))
    Assert-True ($rel -ieq (Get-Item -LiteralPath $agentsMd).FullName.TrimEnd('\')) 'placeholder fixture path is wrong'
    Set-Content -LiteralPath $claudeMd -Value '..\..\repo\AGENTS.MD' -NoNewline
    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "placeholder replace failed: $($r.Text)"
    Test-AbsLink $claudeMd $agentsMd

    # Legacy Codex pointer to AGENTS.MD migrates to the generated file.
    Remove-Item -LiteralPath $codexPointer -Force
    New-Item -ItemType SymbolicLink -Path $codexPointer -Target $agentsMd | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Text -match 'migrated legacy Codex symlink') "expected migration: $($r.Text)"
    Test-AbsLink $codexPointer $codexMd

    # Regular leftover Codex file is left alone without -Force.
    Remove-Item -LiteralPath $codexPointer -Force
    Set-Content -LiteralPath $codexPointer "my own codex rules`n"
    $r = Invoke-Setup
    Assert-True (-not (Get-Item -LiteralPath $codexPointer).LinkType) 'regular Codex file became a symlink'
    Assert-True ((Get-Content -LiteralPath $codexPointer -Raw).Trim() -eq 'my own codex rules') 'regular Codex file was rewritten'
    Assert-True ($r.Text -match 'may be reading stale rules') "expected stale warning: $($r.Text)"

    # Dangling foreign symlink stays.
    Remove-Item -LiteralPath $codexPointer -Force
    New-Item -ItemType SymbolicLink -Path $codexPointer -Target (Join-Path $homeDir 'gone.md') | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Text -match 'preserving foreign symlink') "expected dangling preserve: $($r.Text)"
    Assert-True ((Get-LinkTarget $codexPointer) -match 'gone\.md$') 'dangling symlink was replaced'

    $gitText = Get-Content -LiteralPath $gitConfig -Raw
    Assert-True ($gitText -match 'symlinks\s*=\s*true') "expected isolated core.symlinks true: $gitText"

    Write-Output 'agent instruction setup (Windows) tests passed'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
