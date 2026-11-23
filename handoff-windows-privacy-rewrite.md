# Handoff: Windows PC, after the privacy history rewrite and the move to `global/`

For a Codex or Claude Code agent on a Windows PC, with the user present. Two changes reach this PC together:

- The history of 6 repos was rewritten and force-pushed. The rewrite removed home paths from files and commit messages. Each rewritten commit has a new hash, and tags moved too.
- The global rules and the own skills moved to `agent-scripts/global/` (ADR-0013). The three settings repos track the pointer links into `global/`, so the reset in step 3 sets the pointers.

Rewritten repos: `claude-code-settings` `codex-settings` `dotfiles` `emacs.d` `grok-settings` `pi-settings`. The other repos (for example `agent-scripts`) keep their history: pull them with `git pull --ff-only`.

The procedure ran on `nuc` (Windows 11) on 2026-11-22, in an elevated SSH session. The blocks below are cleaned-up versions of the scripts that ran there. Do the steps in this order, in one sitting: 0, 1, 2, 3, 4, 5, 6, 7.

## Shell

The blocks are for Git Bash. Save each block as a `.sh` file and run it with `bash <file>`. Claude Code runs its Bash tool in Git Bash. Codex runs PowerShell: use `& "C:\Program Files\Git\bin\bash.exe" <file>`. Do not paste long lines into a terminal: wrapped lines broke commands before.

## Rules

- Do not run `git fetch` or `git pull` in a rewritten repo before step 1. A fetch replaces the old `origin/*` refs, and then every old commit looks unpushed. A fetch in `agent-scripts` is safe.
- Do not use a plain `git pull` in a rewritten repo, and do not merge `origin/main` into an old local `main`. A merge or a rebase joins the old history to the new history and brings the home paths back.
- Do not use `git stash` to save work. A stash keeps a ref to the old history, and step 5 then finds hits. Save to patch files (step 2).
- Step 3 deletes local changes. Before step 3, show the user the output of steps 1 and 2, and get an explicit OK.
- Do not commit or push in a rewritten repo. Never commit a pointer change made on Windows.
- Never write the Windows user name, or a path under `C:\Users` or `/c/Users`, in a file or a commit. Write `~`.

## 0. Check that this session can make links

The reset in step 3 writes the pointer links. Without the link privilege, Git writes each link as a text file, and the agents start without the global rules.

Prerequisites (details in `docs/windows.md`): Git for Windows, Git Bash, PowerShell 7.1 or newer, `jq`, `rg`, and Python 3. Run `git config --global core.symlinks true` first. This block reads the check script from `origin/main` and changes no working tree:

```bash
a=~/Projects/agent-scripts
git -C "$a" fetch -q origin || { echo "STOP: fetch of agent-scripts failed"; exit 1; }
t=$(mktemp -d)
git -C "$a" show origin/main:global/bin/check-agent-setup.sh > "$t/check.sh"
bash "$t/check.sh" --preflight; echo "exit $?"
rm -rf "$t"
```

- Both lines must show `✓`.
- If check 2 fails, stop. The user turns on Developer Mode (Settings, System, For developers), or starts the agent with "Run as administrator". An admin account in a normal session cannot make links while Developer Mode is off.
- If check 1 names a missing repo, clone it from `https://github.com/marcuslannister/<repo>.git` after `core.symlinks` is `true`. A new clone has the new history, so skip it in steps 1 to 5.
- If check 1 names a repo with `core.symlinks=false`, run `git -C <repo> config core.symlinks true`. Step 3 then writes its links again.

## 1. Find local work (read-only, before any fetch)

```bash
pat="/Users/""ken"
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d=~/Projects/$r
  [ -e "$d/.git" ] || { echo "== $r: not on this PC"; continue; }
  echo "== $r branch=$(git -C "$d" symbolic-ref --short HEAD 2>/dev/null || echo DETACHED) head=$(git -C "$d" rev-parse --short HEAD)"
  git -C "$d" reflog show --date=short --format='  origin/main %gd %h %gs' origin/main | head -3
  for b in $(git -C "$d" branch --format='%(refname:short)'); do
    echo "  branch $b: not-on-remotes=$(git -C "$d" rev-list --count "$b" --not --remotes) patch-not-in-origin/main=$(git -C "$d" cherry origin/main "$b" | grep -c '^+') hits=$(git -C "$d" log -i -G "$pat" --format=%h "$b" | wc -l | tr -d ' ')"
    git -C "$d" cherry -v origin/main "$b" | grep '^+' | head -5 | sed 's/^/      /'
  done
  n=$(git -C "$d" stash list | wc -l | tr -d ' ')
  for ((i = 0; i < n; i++)); do
    echo "  stash@{$i}: hits=$(git -C "$d" log -i -G "$pat" --format=%h "stash@{$i}" | wc -l | tr -d ' ') $(git -C "$d" stash list --format=%s | sed -n "$((i + 1))p")"
  done
  git -C "$d" status --porcelain -uno | while read -r st f; do
    mode=$(git -C "$d" ls-files -s -- "$f" | cut -d' ' -f1)
    if [ -L "$d/$f" ]; then wt=link; elif [ -e "$d/$f" ]; then wt=file; else wt=deleted; fi
    echo "  changed: $st $f | tracked: $([ "$mode" = 120000 ] && echo link || echo file) | here: $wt"
  done
  echo "  untracked: $(git -C "$d" status --porcelain | grep -c '^??')"
done
echo "== ~/.emacs.d remote: $(git -C ~/.emacs.d remote get-url origin 2>/dev/null || echo none)"
```

How to read it:

- `not-on-remotes` counts commits that no remote ref has. `patch-not-in-origin/main` counts commits whose change is not in `origin/main`: only these can be lost work. On `nuc`, a side branch had 392 commits that were not on any remote, but only 3 of them had this mark. The other 389 were old copies of rewritten commits.
- Both counts are correct only while `origin/main` is still the old history. A `forced-update` line in the `origin/main` reflog shows that a fetch after the rewrite already ran. Then both counts compare with the new history and are much too high (on `nuc`, 3774 in place of 3). Compare with the entry before the `forced-update` line, for example `origin/main@{1}`: `git -C <repo> rev-list --count 'origin/main@{1}..<branch>'` and `git -C <repo> cherry -v 'origin/main@{1}' <branch>`.
- `hits` on `main` are expected, because step 3 replaces `main`. A side branch or a stash with 0 hits can stay as it is. A side branch or a stash with hits must go in step 4, after step 2 saves it.
- A changed file with `tracked: link` or `here: link` is an old pointer link. Step 4 does not restore it: the new tracked links replace it.
- `branch=heads/main` in place of `branch=main`: Git adds `heads/` when another ref also has the name `main`. Step 3 compares the full name `refs/heads/main`, so it still resets this clone. If `git -C <repo> symbolic-ref HEAD` prints `refs/heads/heads/main`, step 3 skips the clone: ask the user.
- A second clone can have another remote. On `nuc`, `~/.emacs.d` is `emacs.d-nn`, which was not rewritten. On the limited PC, `~/.emacs.d` is a link to `~/Projects/emacs.d`. Only the six repos above need these steps. If `~/.emacs.d` is a separate clone of `emacs.d.git`, it has the old history too: stop and ask.

## 2. Save the local work

Run this after step 1. It changes no repo. It writes to `~/rewrite-patches/`.

```bash
out=~/rewrite-patches; mkdir -p "$out"
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d=~/Projects/$r; [ -e "$d/.git" ] || continue
  if [ -n "$(git -C "$d" status --porcelain -uno)" ]; then
    git -C "$d" diff --binary HEAD > "$out/$r.patch"
    git -C "$d" status --porcelain -uno | while read -r st f; do
      if [ -f "$d/$f" ] && [ ! -L "$d/$f" ]; then mkdir -p "$out/files/$r/$(dirname "$f")"; cp "$d/$f" "$out/files/$r/$f"; fi
    done
  fi
  for b in $(git -C "$d" branch --format='%(refname:short)'); do
    if [ "$(git -C "$d" cherry origin/main "$b" | grep -c '^+')" -gt 0 ]; then
      git -C "$d" format-patch -q --ignore-if-in-upstream -o "$out/$r-$(echo "$b" | tr '/' '-')" "origin/main..$b"
    fi
  done
  n=$(git -C "$d" stash list | wc -l | tr -d ' ')
  for ((i = 0; i < n; i++)); do git -C "$d" stash show -p --binary "stash@{$i}" > "$out/$r-stash-$i.patch"; done
done
find "$out" -type f | sed "s#^$HOME#~#"
```

Check that each repo with changes in step 1 has a `.patch` file, and that each changed file that is not a link has a copy in `files/`. If step 1 used `origin/main@{1}` for a repo, use `'origin/main@{1}'` in place of `origin/main` in this block for that repo. Otherwise `format-patch` saves every old commit.

## 3. Reset each clone to the new history (ask the user first)

This deletes the uncommitted changes in these clones. Do it only after step 2 and the user's OK. Untracked files stay.

```bash
git -C ~/Projects/agent-scripts pull -q --ff-only || { echo "STOP: agent-scripts pull failed"; exit 1; }
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d=~/Projects/$r; [ -e "$d/.git" ] || continue
  [ "$(git -C "$d" symbolic-ref HEAD 2>/dev/null)" = refs/heads/main ] || { echo "SKIP $r: not on main"; continue; }
  git -C "$d" fetch -q origin --prune --tags --force || { echo "$r FETCH FAILED"; continue; }
  git -C "$d" reset -q --hard origin/main
  echo "$r reset to $(git -C "$d" rev-parse --short HEAD), changed now: $(git -C "$d" status --porcelain -uno | wc -l | tr -d ' ')"
done
```

`agent-scripts` goes first, so that `global/` exists when the settings repos set their links (ADR-0013). Between the pull and the last reset, some pointers are broken. Finish all steps in this sitting.

## 4. Bring back the real changes

Restore each changed file from step 1 that is not a link, one file at a time:

```bash
restore() { # repo file
  d=~/Projects/$1
  if git -C "$d" apply --3way --include="$2" ~/rewrite-patches/"$1".patch; then
    git -C "$d" reset -q -- "$2"; echo "$1 $2: applied"
  else
    echo "$1 $2: not applied, see the rules below"
  fi
}
restore pi-settings agent/settings.json
```

- Apply one file at a time. When one file in a patch fails, `git apply` applies nothing from that patch.
- `applied`, but `git status` shows no change: the new history already has the change. Nothing to do.
- `does not exist in index`: the new history does not track the file. If `git -C <repo> check-ignore -v <file>` shows that it is ignored, copy it back from `~/rewrite-patches/files/<repo>/`. It stays local. On `nuc`, `pi-settings/agent/mcp.json` was such a file.
- `with conflicts`: merge by hand. Compare the saved copy, the new `HEAD` version, and the upstream change (`git -C <repo> diff <old HEAD> HEAD -- <file>`). Keep only the lines that were local. Then run `git -C <repo> reset -q -- <file>`. On `nuc`, the new history already had 2 of the 3 local edits in `pi-settings/agent/settings.json`, and only `"hideThinkingBlock": true` was local.
- Keep LF line endings. `jq` on Windows writes CRLF: pipe its output through `tr -d '\r'`. Then `git diff` must show only the lines that you changed.
- A restored line can have a Windows home path, because the change was made on this PC. If the tool accepts `~` or a relative path, write that. Otherwise keep the line local. Never commit it. In pi `agent/settings.json`, the paths in `packages`, `extensions`, `skills`, `prompts`, and `themes` start from `~/.pi/agent`, and `~` works: write `agentmemory` for `~/.pi/agent/agentmemory`.
- A file that was deleted on this PC comes back with the reset. Ask the user whether to delete it again. The patch records the deletion.
- Saved commits: apply them with `git -C <repo> am ~/rewrite-patches/<repo>-<branch>/*.patch`, only if the user still wants them. If `am` fails, run `git -C <repo> am --abort`, and ask.
- A side branch or a stash with hits in step 1: after step 2 saved it, delete the branch (`git -C <repo> branch -D <branch>`) or drop the stash (`git -C <repo> stash drop stash@{<n>}`). Ask the user first. A side branch with a remote copy: `git -C <repo> branch -f <branch> origin/<branch>`.
- Pull the repos that were not rewritten with `git pull --ff-only`.

## 5. Check for hits in all refs

```bash
pat="/Users/""ken"
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d=~/Projects/$r; [ -e "$d/.git" ] || continue
  echo "$r hits=$(git -C "$d" log --all -i -G "$pat" --format=%h | wc -l | tr -d ' ') msg_hits=$(git -C "$d" log --all -i --grep "$pat" --format=%h | wc -l | tr -d ' ') jj_refs=$(git -C "$d" for-each-ref refs/jj | wc -l | tr -d ' ') jj_dir=$([ -d "$d/.jj" ] && echo True || echo False)"
done
```

All `hits` and `msg_hits` must be 0. If they are not:

- Find the ref: `git -C <repo> for-each-ref --contains <hash>`.
- A tag: run the fetch from step 3 again. It has `--tags --force`.
- `refs/jj/keep/*` in a repo with `jj_dir=False`: jj does not use these refs. Delete them: `git -C <repo> for-each-ref --format='delete %(refname)' refs/jj | git -C <repo> update-ref --stdin`.
- `refs/jj/*` in a repo with `jj_dir=True`: stop and ask. jj still uses that repo.

## 6. Keep the privacy guard off

This PC does not use the privacy guard. Run `git config --show-origin --get core.hooksPath`.

- No output: the guard is off. Continue.
- Output that points to `~/Projects/agent-scripts/hooks`: the guard is on, maybe from `dotfiles/.gitconfig`. Without gitleaks, these hooks can fail and block each commit. If the setting is in a file that only this PC uses, remove the line there. Do not edit the shared `dotfiles/.gitconfig`, because the Macs need it. Instead, override it for this PC only: `git config --global core.hooksPath .git/hooks`.

## 7. Finish the agent setup

1. If `~/.claude`, `~/.codex`, or `~/.pi` is not a link to its settings repo, see `docs/windows.md`: `pwsh -File global\bin\setup-agent-instructions.ps1`.
2. Run `bash ~/Projects/agent-scripts/agent-tooling/update-local.sh`. It installs the own skills too. It has not run on Windows before: if a step fails, report the output. To install only the own skills, run `bash ~/Projects/agent-scripts/global/bin/install-skills.sh`.
3. Run `bash ~/Projects/agent-scripts/global/bin/check-agent-setup.sh`. All four lines must show `✓`.
4. Make the plugins match the Mac. `~/.codex/config.toml` is local to each PC, so the reset does not bring the Codex marketplaces. Skip each line for a plugin or marketplace that `claude plugin list` or `codex plugin list` already shows:

   ```bash
   claude plugin install ponytail@ponytail
   claude plugin install visual-explainer@visual-explainer-marketplace
   claude plugin install waza@waza
   claude plugin install nowledge-mem@nowledge-community
   codex plugin marketplace add https://github.com/tw93/Waza.git
   codex plugin marketplace add https://github.com/DietrichGebert/ponytail.git
   codex plugin marketplace add https://github.com/nowledge-co/community.git
   codex plugin add waza@waza
   codex plugin add ponytail@ponytail
   codex plugin add nowledge-mem@nowledge-community
   bash ~/Projects/agent-scripts/agent-tooling/update-plugins.sh
   ```

   `update-plugins.sh` applies the lean patches. Its output must have no line that starts with `!!!`. Exception: a PC that uses another memory system (the limited PC uses `agentmemory`) skips the 3 lines with `nowledge` and declines when Claude Code offers to install `nowledge-mem`. There, `!!! nowledge-mem: Codex marketplace upgrade failed` is expected.
5. Bring the Codex context settings to this PC. `~/.codex/config.toml` is local to each PC, so a pull or a reset does not change it. Copy it to `~/rewrite-patches/` first. Then change only these lines, so that they match `~/Projects/codex-settings/config.base.toml`:
   - `model_auto_compact_token_limit = 650000`.
   - In `[features]`, `multi_agent_v2 = true` in place of `multi_agent = true` (the old key is deprecated).
   - Remove the `[mcp_servers.codegraph]` table with its lines. Codegraph runs only in indexed projects, from a project `.codex/config.toml`.

   Then `codex mcp list < /dev/null` must exit 0, must not list `codegraph`, and must print no line with `deprecated`. Do not print the other tables: they can hold credentials.
6. Restart each agent session on this PC, this one too. A running session keeps the rules that it loaded when it started. The first Codex start asks to approve the Nowledge hooks once.
7. Reply to the user: the output of steps 0, 3, 5, and 7.3, what step 4 restored, merged, or left out, the `!!!` lines of step 7.4 if any, the result of step 7.5, and the path of the saved patches.

## Known risks

- Without the guard, a new commit on this PC can add a home path again. Before each push, `git log -i -G "/Users/""ken" origin/main..HEAD --oneline` must print nothing.
- Old commits stay visible on GitHub by SHA until GitHub cleans them. This is accepted.
- With Developer Mode off, only an elevated session can make links. A later pull that changes a link in a normal session writes a text file. `check-agent-setup.sh` finds it.
