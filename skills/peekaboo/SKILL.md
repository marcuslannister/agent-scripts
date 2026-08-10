---
name: peekaboo
description: "macOS screenshots, UI inspect, clicks, typing, app/window automation."
---

# Peekaboo

Use for macOS screen capture, UI inspection, and GUI automation.

## Binary

- Prefer `~/bin/peekaboo` when present; it is Peter's local release copy.
- Else use `peekaboo`.
- Check first: `~/bin/peekaboo --version || peekaboo --version`.

## Mac app host

- Launch `Peekaboo.app` before live capture/automation; the CLI does not auto-launch it.
- The app owns TCC grants and serves `~/Library/Application Support/Peekaboo/bridge.sock`.
- Installed app: `open -a Peekaboo`. Repo build: build the `Apps/Mac/Peekaboo.xcodeproj` `Peekaboo` scheme, then open the resulting `Peekaboo.app`.
- `peekaboo daemon start` is not an app launch; the daemon has separate permissions and `daemon.sock`.
- Verify `peekaboo bridge status --verbose --json` selects `hostKind: gui`; use `--bridge-socket "$HOME/Library/Application Support/Peekaboo/bridge.sock"` when deterministic app routing matters.

## Safety

- Check permissions before capture/automation: `peekaboo permissions status --json`.
- Screenshot needs Screen Recording; clicks/typing/window control need Accessibility.
- On remote Macs, Screenshot may be blocked by missing Screen Recording while
  clicks/typing still work through Accessibility; continue with clicks or DOM
  automation when the target is otherwise knowable.
- Prefer `--json` for machine parsing and `--no-remote` when testing local TCC.
- Do not click/type/destructively automate unless user asked or target is a controlled test.

## Common Commands

```bash
PB="${PEEKABOO_BIN:-$HOME/bin/peekaboo}"
[ -x "$PB" ] || PB="$(command -v peekaboo)"

"$PB" permissions status --json
open -a Peekaboo
"$PB" bridge status --verbose --json
"$PB" list screens --json
"$PB" list apps --json
"$PB" list windows --app Safari --json
"$PB" image --mode screen --screen-index 0 --path /tmp/screen.png --json --no-remote
"$PB" see --app frontmost --path /tmp/frontmost.png --json --annotate
"$PB" tools --json
"$PB" learn
"$PB" click --coords 100,100 --json
"$PB" type "text" --json
"$PB" paste --json
"$PB" hotkey cmd,w --json
```

## Clicking Reliably

Screenshot pixels are **not** click coordinates. `click --coords` takes screen
points; a screenshot of a Retina display is typically twice that, and whatever
scaled rendering you are looking at is a third number. Get the point-space bounds
from `list screens --json` and scale before clicking. A 4848x2952 screenshot of a
2424x1476 screen is a factor of 0.5; against a 2000px-wide rendering of that same
screenshot it is 1.212. Getting this wrong lands every click in roughly the right
region, which is worse than missing outright because it looks like a flaky app.

A click without `--app`, `--pid`, `--window-id`, or a snapshot fails outright:
add `--foreground`.

**The first click into an app that is not frontmost is consumed by focus** and
the control underneath never fires. Issue the same click twice when the target
app may be in the background. Silent no-ops from this cause look exactly like a
wrong coordinate, and cost far more time to diagnose than the extra click costs.

Prefer `paste` over `type` for anything sensitive: `type` puts the value in argv
where it reaches shell history, process listings, and logs, while `paste` moves
it through the clipboard. Clear the clipboard before and after so a stray copy is
detectable.

Element targeting via `see --annotate` is the robust option **when it works**,
but it is not universal. On some machines it returns zero elements for Chrome,
and `list windows --app "Google Chrome"` returns only helper strips rather than
the browser window, leaving no geometry to derive fractions from either. Check
that `see` actually returns elements for your target app before designing around
it, and fall back to scaled coordinates plus a screenshot after each step.

## When a CLI hangs with no output

On macOS, suspect a modal before suspecting the program. A pending Gatekeeper
prompt ("... is an app downloaded from the Internet") silently blocks helper
binaries, and if it opened behind another window there is nothing on screen to
suggest it. Take a screenshot before debugging the CLI. Approving a Gatekeeper
prompt is the user's decision, not yours: surface it rather than clicking Open.

## Workflow

1. Resolve `PB` as above and confirm version when install state matters.
2. For live UI work, launch `Peekaboo.app`; verify the GUI bridge and its permissions.
3. Run `permissions status --json`; if missing TCC, report exact missing grant.
4. For screenshots, use `image`; include `--path`, `--json`, and usually `--no-remote` only when deliberately testing caller-local TCC.
5. For element targeting, run `see --json --annotate`, then click by element id/snapshot.
6. For long-running/change-aware screen capture, use `capture live`; for video frame sampling, use `capture video`.
7. Use `tools --json` for command/tool discovery and `learn` when the full agent guide is useful.
8. Verify output files with `sips -g pixelWidth -g pixelHeight <path>` or view the image.

Docs: `~/Projects/Peekaboo/docs/commands/`.
