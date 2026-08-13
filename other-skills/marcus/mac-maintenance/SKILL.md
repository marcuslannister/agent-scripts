---
name: mac-maintenance
description: "Mac upkeep: pull clean repos under ~/Projects and empty Trash."
---

# Mac Maintenance

Use when Peter asks for Mac cleanup, maintenance, or repo refresh.

Do not update or upgrade Homebrew. Nix manages Homebrew.

## Run

1. Repos under `~/Projects`:

```bash
for repo in ~/Projects/*/.git; do
  dir=${repo:h}
  git -C "$dir" status --short --branch
  git -C "$dir" pull --ff-only
done
```

Skip dirty repos unless Peter explicitly asked to handle them. Report skipped paths.

2. Empty Trash:

```bash
osascript -e 'tell application "Finder" to empty trash'
```

3. Finish with terse counts:

- repos: pulled / skipped / failed
- trash: emptied / failed
