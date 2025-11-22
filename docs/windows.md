# Windows notes

- Symptom: running `./runner` from PowerShell can trigger a "Which app do you want to use?" dialog because Windows doesn't know how to execute the Bash script. Fix by putting Bash and Bun on PATH and wrapping runner.
- Install Git for Windows and ensure the option to add `C:\Program Files\Git\bin` to PATH is enabled (or add it manually). `bash --version` should work in PowerShell.
- Install Bun (needed by `runner`): `irm https://bun.sh/install.ps1 | iex`. The installer drops `bun.exe` in `%USERPROFILE%\.bun\bin` and adds it to the user PATH; restart shells to pick it up.
- PowerShell helper (add to `C:\Users\<you>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`, then reload with `. $PROFILE`):

```powershell
# Helper to run repo runner via Git Bash with Bun on PATH
function runner {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $gitBash = 'C:\Program Files\Git\bin\bash.exe'
    if (-not (Test-Path $gitBash)) {
        Write-Error '[runner] Git Bash not found at C:\Program Files\Git\bin\bash.exe'
        return
    }
    $bunPath = Join-Path $HOME '.bun\bin'
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }
    $scriptPath = Join-Path (Get-Location) 'runner'
    & $gitBash $scriptPath @Args
}
```

- After reloading, `runner echo hi` works from PowerShell without the dialog. You can still call `bash ./runner ...` directly if needed.
