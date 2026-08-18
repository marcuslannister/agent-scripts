---
name: anvil-advanced-ops
description: "Advanced Anvil MCP workflows: compressing verbose shell and context output, 3-layer progressive file disclosure, dispatching heavy Emacs ops (tangles, byte-compile, multi-MB scans) off the main daemon via async eval, and anvil-cron scheduled tasks. Use when tool output is long enough to need compression, when reading large files cheaply, for long-running Emacs operations, or for recurring anvil-cron tasks."
---

## Required modules

These tools only exist when the matching optional module is
enabled in `~/.emacs.d/lisp/init-local-ai.el`. The current list
is:

```elisp
(setq anvil-optional-modules
      '(xlsx pdf http cron browser state shell-filter context disclosure))
```

`state` backs `context` and `shell-filter` with a SQLite blob
store, so it must stay in the list. If a tool below reports as
unknown, check this list first — that is the usual cause, not a
bug in the tool.

Tool names here are bare IDs. In Claude Code they carry the
`mcp__anvil__` prefix, except the eval tools, which live under
`mcp__anvil-eval__`. The two MCP server names are crossed
against their `--server-id` values, so trust the prefix, not the
name.

## org-mode — do not use Anvil org tools

The `org` module stays disabled on purpose (see the comment in
`init-local-ai.el`). Its tools wrote to `~/org` files
independently of the interactive buffers visiting them, which
raced and caused Syncthing sync-conflict storms. No
`anvil-org-*` tool is registered.

Edit org files directly with Read/Edit or the built-in org
tools. For structure only, `file-outline` accepts `format=org`
and returns headlines with line numbers and no bodies.

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
  Recover the raw bytes with `shell-tee-get` only when the
  compressed view hides something material.
- `context-compress` — for non-shell text: API JSON, RAG
  snippets, web extracts, logs from another tool, diffs, code
  excerpts. A content router picks a json/diff/log/code/text
  compressor. Set `store=true` when the raw text may be needed
  later, then recover it with `context-retrieve` and the
  returned `ccr-id`.
- `context-stats` and `shell-gain` — inspect real savings
  instead of guessing whether compression is helping.

Do not use a compressed view as the only source of truth for
legal, financial, safety-critical, or exact numeric work.
Retrieve the raw context before making claims that depend on
exact wording or values.

## Heavy operations — keep them off the main daemon

Long-running Emacs ops (large tangles, byte-compile, multi-MB
scans, full-tree searches) must not run synchronously — they
block every other tool call.

The worker pool runs behind the scenes (`anvil-worker-probe`
reports the lanes; `anvil-worker-reset-pool` recovers a stuck
pool). It is not registered as its own MCP server here, so
`anvil-worker-call` and `mcp__anvil-worker__eval` cannot be
called.

Use async eval instead, for anything that may exceed ~1s:

1. `emacs-eval-async` — returns a job ID at once and leaves
   Emacs responsive.
2. `emacs-eval-result` — poll with that job ID until status is
   `done` or `error`. It also reports queue wait and runtime.
3. `emacs-eval-jobs` — list every job when you need to find a
   stuck one.

Symptom that you should have gone async: the main MCP session
stops accepting tool calls for several seconds.

Keep `emacs-eval` results small. A query that returns an
internal data structure can dump tens of thousands of characters
into context. Return counts, names, or a formatted summary, not
the raw object.

## Scheduled tasks (cron)

If `anvil-cron` tasks are configured (lint, health checks, batch
indexers, etc.), do not re-implement their work ad hoc. Inspect
and trigger them through the cron MCP tools:

- `anvil-cron-list` — what tasks exist and their schedules
- `anvil-cron-status` — last run time, status, recent failures
- `anvil-cron-run` — fire a registered task on demand

Before writing a new ad-hoc script, check `anvil-cron-list` —
the job may already be defined. No tasks are registered on this
machine yet, so today that check returns an empty list.

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
