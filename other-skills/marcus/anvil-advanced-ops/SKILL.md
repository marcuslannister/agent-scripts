---
name: anvil-advanced-ops
description: "Anvil MCP token discipline and heavy-op dispatch: compress long output, 3-layer file disclosure, server-side HTML/JSON extraction, async Emacs eval, anvil-cron tasks, and the org-tools guardrail. Reach for it before reading a large file, fetching a big page, running an Emacs op that may block, scheduling cron work, or editing org."
---

Tool names here are bare IDs. In Claude Code they carry the
`mcp__anvil__` prefix, except the eval tools, which live under
`mcp__anvil-eval__`. The two MCP server names are crossed against
their `--server-id` values, so trust the prefix, not the name.

## org-mode — edit files directly

Edit org files with Read/Edit or the built-in org tools. For
structure, use `file-outline` with `format=org` (Layer 1 below).

The `org` module stays disabled on purpose, and it should stay
that way. Its tools wrote to `~/org` files independently of the
interactive buffers visiting the same files, which raced with
them and caused repeated Syncthing sync-conflict storms.

## Progressive disclosure — three layers

Escalate only as far as you need:

- `file-outline` (Layer 1) — structural outline of an `.el` /
  `.org` / `.md` file, no bodies. Start here on a large file.
- `file-read-snippet` (Layer 2) — one bounded window around a
  given line. Use when the outline told you where to look.
- `file-read` (Layer 3) — full read, or `offset`/`limit` for one
  section. It accepts the `file://PATH#L10-40` citation URI that
  the earlier layers emit, which becomes the default range.

`disclosure-help` prints the full contract.

## Compressing long output

When command output or retrieved context is long, compress it
before it reaches the main reasoning loop.

- `shell-run` — run a shell command and get filtered stdout plus
  a tee ID. It knows the verbose commands (git status / log /
  diff, rg, find, ls, pytest, ert-batch, emacs-batch, make).
  Recover the raw bytes with `shell-tee-get` when the compressed
  view hides something material.
- `context-compress` — for non-shell text: API JSON, RAG
  snippets, web extracts, logs from another tool, diffs, code
  excerpts. A content router picks a json/diff/log/code/text
  compressor. Set `store=true` when the raw text may be needed
  later, then recover it with `context-retrieve` and the
  returned `ccr-id`.
- `context-stats` and `shell-gain` — inspect real savings
  instead of guessing whether compression is helping.

For legal, financial, safety-critical, or exact numeric work,
retrieve the raw context before making claims that depend on
exact wording or values.

## Cheaper HTTP

`http-fetch` extracts server-side, before the body reaches
context:

- `selector` takes a CSS subset (tag, `.class`, `#id`) against
  HTML, typically 20–50× cheaper than the full page.
- `json_path` walks a dotted path through JSON, with `[N]` index
  and `[*]` wildcard.
- `body_mode=auto` (default) spills bodies over 200KB to a temp
  file and returns a head slice plus `body_overflow_path`.
- A no-match still returns the full body with
  `extract_miss: true` — check that flag before you trust an
  empty-looking result.

## Heavy operations — keep them off the main daemon

Long-running Emacs ops (large tangles, byte-compile, multi-MB
scans, full-tree searches) must not run synchronously — they
block every other tool call.

Route anything that may exceed ~1s through async eval:

1. `emacs-eval-async` — returns a job ID at once and leaves
   Emacs responsive.
2. `emacs-eval-result` — poll with that job ID until status is
   `done` or `error`. It also reports queue wait and runtime.
3. `emacs-eval-jobs` — list every job when you need to find a
   stuck one.

A worker pool runs behind this. `anvil-worker-probe` reports the
lanes, and `anvil-worker-reset-pool` recovers a stuck pool.

Symptom that you should have gone async: the main MCP session
stops accepting tool calls for several seconds.

Keep `emacs-eval` results small. A query that returns an internal
data structure can dump tens of thousands of characters into
context. Return counts, names, or a formatted summary, not the
raw object.

## Scheduled tasks (cron)

Inspect and trigger configured `anvil-cron` tasks (lint, health
checks, batch indexers) through the cron MCP tools:

- `anvil-cron-list` — what tasks exist and their schedules
- `anvil-cron-status` — last run time, status, recent failures
- `anvil-cron-run` — fire a registered task on demand

Check `anvil-cron-list` before writing a new ad-hoc script — the
job may already be defined.

## When a tool reports as unknown

The disclosure, compression, and cron tools each come from an
optional Anvil module. An unknown tool almost always means its
module is not enabled, rather than a broken tool. Check
`anvil-optional-modules` in `~/.emacs.d/lisp/init-local-ai.el`.

`state` backs both `context` and `shell-filter` with a SQLite
blob store, so those two need `state` in that list as well.
