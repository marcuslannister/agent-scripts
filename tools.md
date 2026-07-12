# Tools Reference

CLI tools available on Peter's machines. Use these for agentic tasks.

## bird 🐦
Twitter/X CLI for posting, replying, reading tweets.

**Location**: `bird` on PATH (Homebrew); repo `~/Projects/bird`

**Commands**:
```bash
bird tweet "<text>"                    # Post a tweet
bird reply <tweet-id-or-url> "<text>"  # Reply to a tweet
bird read <tweet-id-or-url>            # Fetch tweet content
bird replies <tweet-id-or-url>         # List replies to a tweet
bird thread <tweet-id-or-url>          # Show full conversation thread
bird search "<query>" [-n count]       # Search tweets
bird mentions [-n count]               # Find tweets mentioning @clawdbot
bird whoami                            # Show logged-in account
bird check                             # Show credential sources
```

**Auth**: Uses Firefox cookies by default. Pass `--firefox-profile <name>` to switch.

---

## sonoscli 🔊
Control Sonos speakers over local network (UPnP/SOAP).

**Location**: `sonos` on PATH (Homebrew); repo `~/Projects/sonoscli`

**Commands**:
```bash
sonos discover                         # Find speakers on network
sonos status --name "Room"             # Current playback status
sonos play/pause/stop --name "Room"    # Playback control
sonos next/prev --name "Room"          # Track navigation
sonos volume get/set --name "Room" 25  # Volume control
sonos mute get/toggle --name "Room"    # Mute control

# Grouping
sonos group status                     # Show current groups
sonos group join --name "A" --to "B"   # Join A into B's group
sonos group unjoin --name "Room"       # Make standalone
sonos group party --to "Room"          # Join all to one group

# Spotify (via SMAPI)
sonos smapi search --service "Spotify" --category tracks "query"
sonos open --name "Room" spotify:track:<id>
```

**Known issues**:
- SSDP multicast may fail; use `--ip <speaker-ip>` as fallback

---

## peekaboo 👀
Screenshot, screen inspection, and click automation.

**Location**: `peekaboo` on PATH (Homebrew); repo `~/Projects/Peekaboo`

**Commands**:
```bash
peekaboo capture                       # Take screenshot
peekaboo see                           # Describe what's on screen (OCR)
peekaboo click                         # Click at coordinates
peekaboo list                          # List windows/apps
peekaboo tools                         # Show available tools
peekaboo permissions status            # Check TCC permissions
```

**Requirements**: Screen Recording + Accessibility permissions.

**Docs**: `~/Projects/Peekaboo/docs/commands/`

---

## sweetistics 📊
Twitter/X analytics desktop app (Tauri).

**Location**: `~/Projects/sweetistics`

Use for deeper Twitter data analysis beyond what `bird` provides.

---

## oracle 🧿
Hand prompts + files to other AIs (GPT-5 Pro, etc.).

**Usage**: `npx -y @steipete/oracle --help` (run once per session to learn syntax)

---

## gh
GitHub CLI for PRs, issues, CI, releases.

**Usage**: `gh help`

When someone shares a GitHub URL, use `gh` to read it:
```bash
gh issue view <url> --comments
gh pr view <url> --comments --files
gh run list / gh run view <id>
```

---

## mcporter
MCP server launcher for browser automation, web scraping.

**Usage**: `mcporter --help` (on PATH via Homebrew)

Common servers: `iterm`, `firecrawl`, `XcodeBuildMCP`

---

## Agent Tool Conventions

How to use editing/automation tooling efficiently. (Moved from AGENTS.MD.)

**Anvil MCP edit tools** — prefer over built-in Read/Edit/Write; they ship only the delta and avoid full-file reads.
- `anvil-file-batch` — 3+ edits to the same file (collapse into one call)
- `anvil-file-replace-string` / `anvil-file-replace-regexp` — pinpoint replacement; no full-file read needed
- `anvil-file-insert-at-line` / `anvil-file-delete-lines` / `anvil-file-append` — localized line-level ops
- Built-in `Edit` is fine for small one-offs. For 3+ edits to one file, always use `anvil-file-batch`.

**Org-mode files (.org)** — use `anvil-org-*` instead of Read+Write for section moves, refile, splits, or reading one heading from a large file (10–20× cheaper).
- `anvil-org-read-headline` — read a single subtree
- `anvil-org-read-outline` — outline without bodies
- `anvil-org-edit-body` / `anvil-org-rename-headline` / `anvil-org-update-todo-state` — targeted edits

**Emacs/elisp ops >~1s** (large tangles, byte-compile, multi-MB org scans, full-tree searches) — never run on the main daemon; dispatch through the worker pool.
- From inside Anvil: prefer `anvil-worker-call` over raw `eval`
- If the worker is its own MCP server, target `mcp__anvil-worker__eval` directly
- Symptom you should have used the worker: the main MCP session stalls for several seconds.

**Scheduled tasks / recurring jobs** — before writing a new ad-hoc script, check whether the job already exists.
- `anvil-cron-list` — tasks and schedules
- `anvil-cron-status` — last run, status, recent failures
- `anvil-cron-run` — fire a registered task on demand
- Don't re-implement work an existing cron task already does.
