# Handoff: Windows PC, after the privacy history rewrite

The history of 6 repos was rewritten and force-pushed. The rewrite removed home paths from files and commit messages. GitHub has 0 hits in all refs. Each rewritten commit has a new hash, and tags moved too. Do the steps on the Windows PC in this order: 1, 2, 3, 4, 5. Step 5 keeps the privacy guard off on this PC.

Repos: claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings

The other repos (agent-scripts, macwhisper-mcp, nix-config, proxy-config) keep their history. Only pull them with `git pull --ff-only`.

Use PowerShell. Save each block as a `.ps1` file and run the file. Do not paste long lines into the terminal: on the Mac, wrapped lines broke two commands, and only half of each command ran.

## Rules from the Mac run

- Do NOT run `git fetch` or `git pull` before step 1. A fetch replaces the old `origin/*` refs, and then every old commit looks unpushed.
- Do NOT merge `origin/main` into an old local `main`. The merge joins the old history to the new history and brings the hits back. If you have new commits on the old history, cherry-pick them onto `origin/main` (step 3).
- Do not push a repo until step 4 shows 0 hits for it.

## 1. Find work that is not pushed (before any fetch)

This changes nothing.

```powershell
$repos = 'claude-code-settings','codex-settings','dotfiles','emacs.d','grok-settings','pi-settings'
foreach ($r in $repos) {
  $d = "$HOME\Projects\$r"; if (-not (Test-Path "$d\.git")) { "== $r MISSING"; continue }
  "== $r branch=$(git -C $d symbolic-ref --short HEAD)"
  git -C $d status --porcelain -uno
  git -C $d log --oneline --branches --not --remotes
  git -C $d stash list
  git -C $d branch --format='  side branch %(refname:short)' | Select-String -NotMatch ' (main|master)$'
}
```

## 2. Save that work

For each repo with output in step 1:

- Commits: `git -C <repo> format-patch origin/main..main -o $HOME\rewrite-patches\<repo>`
- Changed tracked files: `git -C <repo> stash push -m pre-rewrite`

Run step 1 again. Each repo must show no changed files and no unpushed commits.

## 3. Reset each clone to the rewritten history

This DELETES uncommitted and unpushed work in these clones. Do it only after step 2.

```powershell
$repos = 'claude-code-settings','codex-settings','dotfiles','emacs.d','grok-settings','pi-settings'
foreach ($r in $repos) {
  $d = "$HOME\Projects\$r"; if (-not (Test-Path "$d\.git")) { continue }
  git -C $d fetch -q origin --prune --tags --force
  if ($LASTEXITCODE -ne 0) { "$r FETCH FAILED"; continue }
  git -C $d reset -q --hard origin/main
  "$r reset to $(git -C $d rev-parse --short HEAD)"
}
```

Then:

1. Apply saved patches: `git -C <repo> am $HOME\rewrite-patches\<repo>\*.patch`. If `am` fails, run `git -C <repo> am --abort` and cherry-pick the commits one by one.
2. Restore saved changes: `git -C <repo> stash pop`.
3. Side branches keep the old history. For each side branch with a remote copy: `git -C <repo> branch -f <branch> origin/<branch>`. Delete a side branch that has no remote copy only after you save its commits.
4. Pull the other repos: `git -C $HOME\Projects\<repo> pull --ff-only`.

## 4. Check for hits in all refs

```powershell
$repos = 'claude-code-settings','codex-settings','dotfiles','emacs.d','grok-settings','pi-settings'
$pat = '/Users/' + 'ken'
foreach ($r in $repos) {
  $d = "$HOME\Projects\$r"; if (-not (Test-Path "$d\.git")) { continue }
  $hits = (git -C $d log --all -i -G $pat --format=%h | Measure-Object).Count
  $msgs = (git -C $d log --all -i --grep $pat --format=%h | Measure-Object).Count
  $jj = (git -C $d for-each-ref refs/jj | Measure-Object).Count
  "$r hits=$hits msg_hits=$msgs jj_refs=$jj jj_dir=$(Test-Path "$d\.jj")"
}
```

All `hits` and `msg_hits` must be 0. If they are not:

- Find the ref: `git -C <repo> for-each-ref --contains <hash>`.
- A tag: run the fetch from step 3 again. It has `--tags --force`.
- `refs/jj/keep/*` in a repo with `jj_dir=False`: jj does not use these refs. Delete them: `git -C <repo> for-each-ref --format='delete %(refname)' refs/jj | git -C <repo> update-ref --stdin`.
- `refs/jj/*` in a repo with `jj_dir=True`: stop and ask. jj still uses that repo.

## 5. Keep the privacy guard off

This PC does not use the privacy guard. Check that Git does not try to run it:

```powershell
git config --show-origin --get core.hooksPath
```

- No output: the guard is off. You are done.
- Output that points to `~/Projects/agent-scripts/hooks`: the guard is on, maybe from `dotfiles/.gitconfig`. Without gitleaks and symlink support, these hooks can fail and block each commit. If the setting is in a file that only this PC uses, remove the line there. Do not edit the shared `dotfiles/.gitconfig`, because the Macs need it. Instead, override it for this PC only: `git config --global core.hooksPath .git/hooks`.

## Known risks

- Nothing here was tested on Windows.
- Without the guard, a new commit on this PC can add a home path again. Check before each push: `git log -i -G ('/Users/' + 'ken') origin/main..HEAD --oneline` must print nothing.
- Old commits stay visible on GitHub by SHA until GitHub cleans them. This is accepted.
