#Requires -Version 7
# Windows counterpart of setup-agent-instructions-test.sh.
# Covers the .ps1 public contract only: relative links, placeholders, -Force, PowerShell 7 only.
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('setup-instr-' + [guid]::NewGuid().ToString('n'))
$fixture = Join-Path $tmp 'repo'
$homeDir = Join-Path $tmp 'home'
$gitConfig = Join-Path $tmp 'gitconfig'
$setupPs1 = Join-Path $fixture 'bin\setup-agent-instructions.ps1'
# The pwsh that runs this test, by full path: a bare name needs a PATH entry that an SSH session may lack.
$shell = (Get-Process -Id $PID).Path

function Assert-True([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw $Msg }
}

function Get-LinkTarget([string]$Path) {
    return @((Get-Item -LiteralPath $Path -Force).Target)[0]
}

# The link must be a symlink with this exact relative target, and it must resolve:
# a file link reads like the wanted file, a directory link lists the wanted folder.
function Test-RelLink([string]$Pointer, [string]$Want, [string]$ExpectedRel) {
    $item = Get-Item -LiteralPath $Pointer -Force
    Assert-True ($item.LinkType -eq 'SymbolicLink') "not a symlink: $Pointer"
    $raw = Get-LinkTarget $Pointer
    Assert-True (-not [IO.Path]::IsPathRooted($raw)) "expected relative symlink: $Pointer -> $raw"
    Assert-True (($raw -replace '/', '\') -ieq $ExpectedRel) "target mismatch: $Pointer -> $raw (want $ExpectedRel)"
    if (Test-Path -LiteralPath $Want -PathType Container) {
        Assert-True (@(Get-ChildItem -LiteralPath $Pointer).Count -eq @(Get-ChildItem -LiteralPath $Want).Count) "directory link does not list its target: $Pointer"
    } else {
        Assert-True ((Get-Content -LiteralPath $Pointer -Raw) -eq (Get-Content -LiteralPath $Want -Raw)) "link does not read its target: $Pointer"
    }
}

function Invoke-Setup {
    param([switch]$Force, [string]$Home1 = $homeDir, [string]$Exe = $shell)
    $argList = @('-NoProfile', '-NonInteractive', '-File', $setupPs1)
    if ($Force) { $argList += '-Force' }
    $prev = @{
        HOME              = $env:HOME
        USERPROFILE       = $env:USERPROFILE
        GIT_CONFIG_GLOBAL = $env:GIT_CONFIG_GLOBAL
    }
    try {
        $env:HOME = $Home1
        $env:USERPROFILE = $Home1
        $env:GIT_CONFIG_GLOBAL = $gitConfig
        $text = & $Exe @argList 2>&1 | ForEach-Object { "$_" }
        return @{ Code = $LASTEXITCODE; Text = ($text -join "`n") }
    } finally {
        $env:HOME = $prev.HOME
        $env:USERPROFILE = $prev.USERPROFILE
        $env:GIT_CONFIG_GLOBAL = $prev.GIT_CONFIG_GLOBAL
    }
}

New-Item -ItemType Directory -Path (Join-Path $fixture 'bin') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fixture 'rules') | Out-Null
New-Item -ItemType Directory -Path $homeDir | Out-Null
New-Item -ItemType File -Path $gitConfig | Out-Null
Copy-Item (Join-Path $RepoRoot 'bin\setup-agent-instructions.ps1') $setupPs1
Set-Content -LiteralPath (Join-Path $fixture 'AGENTS.md') "shared rules`n"
Set-Content -LiteralPath (Join-Path $fixture 'rules\topic.md') "topic rules`n"
$agentsMd = Join-Path $fixture 'AGENTS.md'
$codexMd = Join-Path $fixture 'AGENTS.codex.md'
$rulesDir = Join-Path $fixture 'rules'
$claudeMd = Join-Path $homeDir '.claude\CLAUDE.md'
$claudeRules = Join-Path $homeDir '.claude\agent-rules'
$claudeOldRules = Join-Path $homeDir '.claude\rules'
$piMd = Join-Path $homeDir '.pi\agent\AGENTS.md'
$codexPointer = Join-Path $homeDir '.codex\AGENTS.md'
# The targets that the Bash setup makes for this layout (home and repo side by side).
$relAgents = '..\..\repo\AGENTS.md'
$relRules = '..\..\repo\rules'
$relCodex = '..\..\repo\AGENTS.codex.md'
$relPiCodex = '..\..\..\repo\AGENTS.codex.md'

try {
    $r = Invoke-Setup
    Assert-True ($r.Code -ne 0) 'expected setup to fail without AGENTS.codex.md'
    Assert-True ($r.Text -match 'global/bin/build-codex-instructions\.sh') "expected the build hint: $($r.Text)"

    Set-Content -LiteralPath $codexMd "generated`n"

    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "first setup failed: $($r.Text)"
    Test-RelLink $claudeMd $agentsMd $relAgents
    Test-RelLink $claudeRules $rulesDir $relRules
    Test-RelLink $piMd $codexMd $relPiCodex
    Test-RelLink $codexPointer $codexMd $relCodex
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
    Test-RelLink $claudeMd $agentsMd $relAgents

    # An absolute symlink to the same place (an older setup made these) is rewritten as relative.
    Remove-Item -LiteralPath $claudeRules -Force
    New-Item -ItemType SymbolicLink -Path $claudeRules -Target $rulesDir | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "absolute rewrite failed: $($r.Text)"
    Assert-True ($r.Text -notmatch [regex]::Escape("preserving foreign symlink: $claudeRules")) 'equivalent absolute symlink treated as foreign'
    Test-RelLink $claudeRules $rulesDir $relRules

    # A relative symlink to the same place in another spelling is normalized.
    Remove-Item -LiteralPath $claudeRules -Force
    New-Item -ItemType SymbolicLink -Path $claudeRules -Target '..\..\repo\.\rules' | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "relative normalize failed: $($r.Text)"
    Assert-True ($r.Text -notmatch [regex]::Escape("preserving foreign symlink: $claudeRules")) 'equivalent relative symlink treated as foreign'
    Test-RelLink $claudeRules $rulesDir $relRules

    # Git-for-Windows placeholder: a one-line relative path file.
    Remove-Item -LiteralPath $claudeMd -Force
    $rel = [IO.Path]::GetFullPath((Join-Path (Split-Path $claudeMd) $relAgents))
    Assert-True ($rel -ieq (Get-Item -LiteralPath $agentsMd).FullName.TrimEnd('\')) 'placeholder fixture path is wrong'
    Set-Content -LiteralPath $claudeMd -Value $relAgents -NoNewline
    $r = Invoke-Setup
    Assert-True ($r.Code -eq 0) "placeholder replace failed: $($r.Text)"
    Test-RelLink $claudeMd $agentsMd $relAgents

    # The pre-rename ~/.claude/rules pointer is ours and goes.
    New-Item -ItemType SymbolicLink -Path $claudeOldRules -Target $relRules | Out-Null
    $r = Invoke-Setup
    Assert-True (-not (Test-Path -LiteralPath $claudeOldRules)) 'legacy ~/.claude/rules pointer was kept'
    Assert-True ($r.Text -match 'removed legacy pointer') "expected legacy removal: $($r.Text)"

    # Legacy Codex pointer to AGENTS.md migrates to the generated file.
    Remove-Item -LiteralPath $codexPointer -Force
    New-Item -ItemType SymbolicLink -Path $codexPointer -Target $agentsMd | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Text -match 'migrated legacy symlink') "expected migration: $($r.Text)"
    Test-RelLink $codexPointer $codexMd $relCodex

    # Legacy Pi pointer to AGENTS.md migrates to the generated file.
    Remove-Item -LiteralPath $piMd -Force
    New-Item -ItemType SymbolicLink -Path $piMd -Target $agentsMd | Out-Null
    $r = Invoke-Setup
    Assert-True ($r.Text -match 'migrated legacy symlink') "expected Pi migration: $($r.Text)"
    Test-RelLink $piMd $codexMd $relPiCodex

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

    # ~/.claude and ~/.pi are links into other folders (the settings repos). The
    # target starts at the physical folder, and the pointer reads through the link.
    $home2 = Join-Path $tmp 'home2'
    $claudeRepo = Join-Path $tmp 'settings\claude'
    $piRepo = Join-Path $tmp 'settings\pi'
    New-Item -ItemType Directory -Path $home2, $claudeRepo, (Join-Path $piRepo 'agent') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $home2 '.claude') -Target '..\settings\claude' | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $home2 '.pi') -Target '..\settings\pi' | Out-Null
    $r = Invoke-Setup -Home1 $home2
    Assert-True ($r.Code -eq 0) "setup through folder links failed: $($r.Text)"
    Test-RelLink (Join-Path $claudeRepo 'CLAUDE.md') $agentsMd '..\..\repo\AGENTS.md'
    Test-RelLink (Join-Path $claudeRepo 'agent-rules') $rulesDir '..\..\repo\rules'
    Test-RelLink (Join-Path $piRepo 'agent\AGENTS.md') $codexMd '..\..\..\repo\AGENTS.codex.md'
    Test-RelLink (Join-Path $home2 '.codex\AGENTS.md') $codexMd '..\..\repo\AGENTS.codex.md'
    # The same pointers, opened through the folder links, as an agent opens them.
    Assert-True ((Get-Content -LiteralPath (Join-Path $home2 '.claude\CLAUDE.md') -Raw) -eq (Get-Content -LiteralPath $agentsMd -Raw)) 'CLAUDE.md does not read through the .claude link'
    Assert-True ((Get-Content -LiteralPath (Join-Path $home2 '.pi\agent\AGENTS.md') -Raw) -eq (Get-Content -LiteralPath $codexMd -Raw)) 'AGENTS.md does not read through the .pi link'
    Assert-True ((Test-Path -LiteralPath (Join-Path $home2 '.claude\agent-rules\topic.md'))) 'agent-rules does not list through the .claude link'
    $r = Invoke-Setup -Home1 $home2
    Assert-True ($r.Text -match 'instruction pointers up to date') "expected up to date through folder links: $($r.Text)"

    # PowerShell 7 only: Windows PowerShell 5.1 would write absolute targets, so it must stop.
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps51) {
        $home3 = Join-Path $tmp 'home3'
        New-Item -ItemType Directory -Path $home3 | Out-Null
        $r = Invoke-Setup -Home1 $home3 -Exe $ps51
        Assert-True ($r.Code -ne 0) "Windows PowerShell 5.1 ran the setup: $($r.Text)"
        Assert-True ($r.Text -match '#requires') "expected a #requires refusal: $($r.Text)"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $home3 '.claude'))) 'Windows PowerShell 5.1 made a pointer'
    } else {
        Write-Output 'skipped the Windows PowerShell 5.1 refusal case: powershell.exe not found'
    }

    $gitText = Get-Content -LiteralPath $gitConfig -Raw
    Assert-True ($gitText -match 'symlinks\s*=\s*true') "expected isolated core.symlinks true: $gitText"

    Write-Output 'agent instruction setup (Windows) tests passed'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
