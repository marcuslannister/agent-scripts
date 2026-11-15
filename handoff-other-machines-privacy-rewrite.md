# Handoff: other machines, before and after the privacy history rewrite

On the main Mac, the history of 6 repos will be rewritten and force-pushed. Do part A on each other machine (the other Mac, each Linux host) BEFORE the rewrite. Do part B AFTER the main Mac reports that all force-pushes are done.

Repos: claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings

What changes: personal home directory paths are removed from files and commit messages. Author and committer emails do not change. Each commit that holds a hit, and each later commit, gets a new hash. Tags move too. The other repos (agent-scripts, macwhisper-mcp, nix-config, proxy-config) keep their history: only pull them.

## Status (2026-10-26)

- The rewrite is DONE and pushed for all six repos. GitHub has 0 hits in all refs.
- emacs.d was rewritten twice. The first run also changed 645 upstream commits (a signed purcell merge lost its signature). A repair restored the old history and rewrote only the repository owner's commits. Upstream commits keep their hashes. Part B fetches the final state, so one run is enough.
- Other machine: part A is done and clean. Next: part B, then part C.
- The Mac that is not reachable now: use part D, not part A.
- On every machine, `git pull --ff-only` the other repos too (agent-scripts has new CI and test fixes).

## A. Before the rewrite: find unpushed work

Run on each machine. It changes nothing.

```sh
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d="$HOME/Projects/$r"; [ -d "$d/.git" ] || continue
  git -C "$d" fetch -q origin
  dirty=$(git -C "$d" status --porcelain | wc -l | tr -d ' ')
  ahead=$(git -C "$d" log --oneline --branches --not --remotes | wc -l | tr -d ' ')
  stashes=$(git -C "$d" stash list | wc -l | tr -d ' ')
  echo "$r dirty=$dirty unpushed=$ahead stashes=$stashes"
done
```

If any number is not 0: push the work now (before the rewrite), or save it as a patch with `git -C <repo> format-patch origin/main -o ~/rewrite-patches/<repo>`. Report the result to the main Mac. Do not commit to these repos again until part B is done.

## B. After the rewrite: reset each clone

This DELETES uncommitted and unpushed work in these clones. Do it only after part A is clean.

```sh
for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
  d="$HOME/Projects/$r"; [ -d "$d/.git" ] || continue
  b=$(git -C "$d" symbolic-ref --short HEAD)
  git -C "$d" fetch origin --prune --tags --force &&
  git -C "$d" reset --hard "origin/$b" &&
  echo "$r reset to $(git -C "$d" rev-parse --short HEAD)"
done
```

Then apply saved patches, if any: `git -C <repo> am ~/rewrite-patches/<repo>/*.patch`.

Other branches than the current one keep the old history. List them with `git -C <repo> branch -vv`. Delete or reset each one.

## C. Turn on the privacy guard

1. Make sure `~/Projects/agent-scripts` exists. If it does not, the global hooks path points to nothing and Git runs no hooks, with no warning.
2. Apply the config: `darwin-rebuild switch --flake ~/Projects/nix-config` on a Mac, or the `home-manager switch` command for that host on Linux. This sets `core.hooksPath` through `dotfiles/.gitconfig`, and installs `gitleaks`.
3. Check:
   - `git config --get core.hooksPath` prints `~/Projects/agent-scripts/hooks`.
   - `command -v gitleaks` finds the tool.
4. Check that local hooks still run: if a repo has its own `.git/hooks/pre-commit`, make a test commit there and see that the hook runs.

## D. A machine you reach only after the rewrite

Do NOT run `git fetch` or part A first. A fetch replaces the old `origin/*` refs, and then every old commit looks unpushed. `pull.ff = only` makes `git pull` fail safely here, so a pull does no harm, but it does not help either.

1. Find work that was not pushed before the rewrite. This uses the old `origin/*` refs, so do it before any fetch:

   ```sh
   for r in claude-code-settings codex-settings dotfiles emacs.d grok-settings pi-settings; do
     d="$HOME/Projects/$r"; [ -d "$d/.git" ] || continue
     echo "== $r"
     git -C "$d" status --porcelain -uno
     git -C "$d" log --oneline --branches --not --remotes
     git -C "$d" stash list
   done
   ```

2. For each repo with output: save commits with `git -C <repo> format-patch origin/main..main -o ~/rewrite-patches/<repo>`, and save tracked changes with `git -C <repo> stash push -m pre-rewrite`.
3. Run part B, then `git am` the patches and `git stash pop`.
4. Run part C.

## Known risks

- A Linux host that gets `dotfiles` as a Nix store copy gets the new `.gitconfig` only after the rebuild in C2.
- Old commits stay visible on GitHub by SHA until GitHub cleans them. This is accepted.
