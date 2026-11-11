# curl reference — Metrix.Bar local API

Setup (values come from Settings → Agent):

```sh
export MB=http://127.0.0.1:6387 # Replace with the address from Settings → Agent
export TOKEN='token-from-settings'
AUTH="Authorization: Bearer $TOKEN"
ID=github-repo # Use the actual installed ID from GET /v0/dashboards
```

## Health check

`GET /v0/health` requires no authentication and returns app status and uptime:

```sh
curl -fsS $MB/v0/health
```

## Validate a .bar file

Body is the raw file as `text/plain`; returns `{valid: true}` or diagnostics with code, message, and optional path:

```sh
curl -fsS -X POST -H "$AUTH" -H "Content-Type: text/plain" \
  --data-binary @/tmp/dash.bar \
  $MB/v0/validate
```

## List all dashboards

Returns `{dashboards: [...]}` containing dashboard summaries with current status and revisions:

```sh
curl -fsS -H "$AUTH" $MB/v0/dashboards
```

## Get dashboard snapshot

Returns complete dashboard state `{id, status, error, updated_at, revision, inputs, view}`:

```sh
curl -fsS -H "$AUTH" $MB/v0/dashboards/$ID
```

## Read dashboard source

Fetches raw `.bar` text with an `ETag` header:

```sh
curl -fsS -H "$AUTH" $MB/v0/dashboards/$ID/source -D /tmp/headers.txt -o /tmp/current.bar
grep -i '^etag:' /tmp/headers.txt
```

## Create a dashboard

Pass the raw `.bar` file content as `text/plain`:

```sh
curl -fsS -X POST -H "$AUTH" -H "Content-Type: text/plain" \
  --data-binary @/tmp/dash.bar \
  $MB/v0/dashboards
```

## Update a dashboard source (optimistic concurrency)

Send `If-Match` with the quoted `ETag` from the previous source fetch. On HTTP 412, re-fetch, reconcile, and retry:

```sh
curl -fsS -X PUT -H "$AUTH" -H "Content-Type: text/plain" \
  -H 'If-Match: "<etag-from-GET>"' \
  --data-binary @/tmp/dash.bar \
  $MB/v0/dashboards/$ID/source
```

## Delete a dashboard

Removes the dashboard and its associated secrets:

```sh
curl -fsS -X DELETE -H "$AUTH" $MB/v0/dashboards/$ID
```

## Inspect and set input values

```sh
# Get inputs status (secret inputs only report is_set: true)
curl -fsS -H "$AUTH" $MB/v0/dashboards/$ID/inputs

# Set public inputs
curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
  $MB/v0/dashboards/$ID/inputs \
  -d '{"inputs": {"repository": "golang/go"}}'

# Store a secret value (write-only)
curl -fsS -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"value": "ghp_xxxxxxxxxxxx"}' \
  $MB/v0/dashboards/$ID/secrets/token
```

## Trigger refresh and custom events

```sh
# Force an immediate refresh cycle
curl -fsS -X POST -H "$AUTH" $MB/v0/dashboards/$ID/refresh

# Dispatch an event to the Worker export event(name, payload)
curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"action": "toggle-mode"}' \
  $MB/v0/dashboards/$ID/events/click
```

## Choose dashboard entrances and opening mode

Configure entrances, default opening mode, and per-source opening modes (e.g. Menu Bar and Right Sidebar entrances, default Flyout, with Keyboard Shortcut and Right Sidebar opening Dialog):

```sh
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"placements":["menubar","sidebar-right"],"open_mode":"flyout","open_modes":{"shortcut":"dialog","sidebar-right":"dialog"}}' \
  "$MB/v0/dashboards/$ID/settings"
```

HTTP 200 returns effective settings, for example `{"id":"example","placements":["menubar","sidebar-right"],"open_mode":"flyout","window_style":"standard","open_modes":{"menubar":"flyout","sidebar-left":"flyout","sidebar-right":"dialog","sidebar-bottom":"flyout","shortcut":"dialog"}}`. An empty entrance list stays `[]`. `open_modes` always returns the resolved effective modes across all five sources, never `null`.

Change only the default opening mode, then restore only its author default:

```sh
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"open_mode":"flyout"}' "$MB/v0/dashboards/$ID/settings"
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"open_mode":null}' "$MB/v0/dashboards/$ID/settings"
```

Clear all per-source overrides (all sources revert to following the default opening mode):

```sh
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"open_modes":null}' "$MB/v0/dashboards/$ID/settings"
```

Disable all visual entrances, then restore only the author's default entrances:

```sh
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"placements":[]}' "$MB/v0/dashboards/$ID/settings"
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"placements":null}' "$MB/v0/dashboards/$ID/settings"
```

Restore default entrances, default opening mode, window appearance, and clear all per-source overrides:

```sh
curl -fsS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"placements":null,"open_mode":null,"open_modes":null,"window_style":null}' "$MB/v0/dashboards/$ID/settings"
```

The endpoint accepts `placements`, `open_mode`, `open_modes`, and `window_style`, and at least one must be present. Omitted fields stay unchanged; `null` clears only that override and restores its author default. Placements accept any unique combination of `menubar`, `sidebar-left`, `sidebar-right`, and `sidebar-bottom`. Opening mode accepts `flyout`, `dialog`, or `window`. `window_style` accepts `standard`, `immersive`, or `null` to restore the author default; fullscreen is a separate window state. `open_modes` accepts an object replacing all per-source overrides (keys: `menubar`, `sidebar-left`, `sidebar-right`, `sidebar-bottom`, `shortcut`; values: `flyout`, `dialog`, `window`), or `null`/`{}` to clear them. Unknown fields (including the removed `show_in_menu_bar`), wrong types, duplicates, or invalid values return 400. Official and third-party dashboards use the same settings. Programmatic panel actions follow the effective default opening mode and keep the `{open}` response. With Window as the default mode, `open()` focuses an existing window, restoring it first if minimized; a different container is reopened in the default mode. Explicit `toggle()` closes any open panel and `close()` closes the window. Minimizing still returns `{open: true}` and sends no lifecycle collapse event. Send `{"open_mode":"window","window_style":"immersive"}` for an immersive native window.

## Current types and isolated runtime check

```sh
curl -fsS -H "$AUTH" "$MB/v0/types" -o /tmp/metrixbar.d.ts
# jq encodes the source safely; add inputs, fixture, or screenshot as needed.
jq -n --rawfile source /tmp/dash.bar '{source:$source,tree:true}' > /tmp/check.json
curl -fsS -H "$AUTH" -H 'Content-Type: application/json' \
  --data-binary @/tmp/check.json "$MB/v0/check"
```

Inspect `valid` and `diagnostics`, even after HTTP 200. IndexedDB uses isolated temporary databases removed after the check. Without fixtures, the check can perform declared network/file I/O.

## Reload source edited on disk

```sh
curl -fsS -X POST -H "$AUTH" "$MB/v0/dashboards/$ID/reload"
```

Reload preflights against temporary IndexedDB snapshots, then rebuilds the live Worker. Initialization, migrations, and external operations may run again; a failed preflight preserves the previous runtime, while successful preflight does not guarantee live startup. Refresh only requests new data in the existing Worker.
