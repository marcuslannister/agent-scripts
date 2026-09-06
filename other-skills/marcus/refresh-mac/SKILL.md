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
  echo "=== $dir ==="
  git -C "$dir" pull --ff-only
done
```

Attempt the pull on every repo, dirty or clean — `--ff-only` already refuses safely
when a local change would be overwritten, so there is no need to pre-filter on
`git status`. A dirty repo whose local changes don't touch the incoming diff pulls
cleanly; one that conflicts fails on its own and gets reported as failed, with the
git error kept for the report. Report failed paths.

2. Empty Trash:

```bash
osascript -e 'tell application "Finder" to empty trash'
```

3. Apply the Nix Darwin configuration from the flake directory:

```bash
sudo darwin-rebuild switch --flake . --impure
```

4. Finish with terse counts:

- repos: pulled / skipped / failed
- trash: emptied / failed
- Nix Darwin: applied / failed
