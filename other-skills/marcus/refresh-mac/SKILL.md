---
name: refresh-mac
description: "Mac upkeep: pull repos under ~/Projects, empty Trash, and apply the Nix Darwin configuration. Use when asked for Mac cleanup, maintenance, or repo refresh."
---

# Refresh Mac

Use when user asks for Mac cleanup, maintenance, or repo refresh.

Do not update or upgrade Homebrew. Nix manages Homebrew.

## Run

1. Repos under `~/Projects`:

```bash
for repo in ~/Projects/*/.git; do
  dir=${repo:h}
  name=${dir:t}
  dirty=no
  [ -n "$(git -C "$dir" status --porcelain)" ] && dirty=yes
  out=$(git -C "$dir" pull --ff-only 2>&1)
  if [ $? -ne 0 ]; then
    result=failed
  elif print -r -- "$out" | grep -q "Already up to date"; then
    result=up-to-date
  else
    result=pulled
  fi
  echo "$name|$dirty|$result"
done
```

Attempt the pull on every repo, dirty or clean — `--ff-only` already refuses safely
when a local change would be overwritten, so checking `git status` first is only for
the report, not to gate the pull. A dirty repo whose local changes don't touch the
incoming diff pulls cleanly; one that conflicts fails on its own and gets reported as
failed, with the git error kept for the report.

2. Empty Trash:

```bash
osascript -e 'tell application "Finder" to empty trash'
```

3. Apply the Nix Darwin configuration from the flake directory:

```bash
sudo darwin-rebuild switch --flake . --impure
```

4. Finish with a status table (one row per repo) and terse counts:

| Repo | Dirty | Result |
|---|---|---|
| agent-scripts | no | up-to-date |
| nix-config | no | pulled |

- repos: pulled / up-to-date / failed (dirty: N)
- trash: emptied / failed
- Nix Darwin: applied / failed
