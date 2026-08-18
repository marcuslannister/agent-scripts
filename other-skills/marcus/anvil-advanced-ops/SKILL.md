---
name: anvil-advanced-ops
description: "Advanced Anvil MCP workflows: dispatching heavy Emacs ops (tangles, byte-compile, multi-MB scans) off the main daemon via async eval, anvil-cron scheduled tasks, and cutting tokens with progressive file disclosure and server-side HTTP extraction. Use for long-running Emacs operations, recurring anvil-cron tasks, reading large files cheaply, or fetching large web/JSON payloads."
---

## org-mode — do not use Anvil org tools

Anvil's `org` module is disabled on this machine (see
`~/.emacs.d/lisp/init-local-ai.el`). It raced with interactive
Emacs buffers and caused Syncthing sync-conflict storms on org
files. No `anvil-org-*` tool is registered.

Edit org files directly with Read/Edit or the built-in org
tools. Do not reach for `anvil-org-edit-body`,
`anvil-org-rename-headline`, or `anvil-org-update-todo-state` —
they are not available.

For structure only, one cheap read still works:
`anvil-file-outline` accepts `format=org` and returns headlines
with line numbers and no bodies. Use it to orient in a large org
file, then Read the range you need.

## Heavy operations — keep them off the main daemon

Long-running Emacs ops (large tangles, byte-compile, multi-MB
org scans, full-tree searches) must not run synchronously — they
block every other tool call.

The worker pool is running (`anvil-worker-probe` reports the
lanes; `anvil-worker-reset-pool` recovers a stuck pool). But it
is not registered as its own MCP server here, so
`anvil-worker-call` and `mcp__anvil-worker__eval` cannot be
called.

Use async eval instead, for anything that may exceed ~1s:

1. `mcp__anvil-eval__emacs-eval-async` — returns a job ID at
   once and leaves Emacs responsive.
2. `mcp__anvil-eval__emacs-eval-result` — poll with that job ID
   until status is `done` or `error`. It also reports queue wait
   and runtime.
3. `mcp__anvil-eval__emacs-eval-jobs` — list every job when you
   need to find a stuck one.

Symptom that you should have gone async: the main MCP session
stops accepting tool calls for several seconds.

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

## Cutting tokens on reads and fetches

There is no compression layer here: `shell-run`,
`context-compress`, `context-retrieve`, `context-stats`, and
`shell-gain` are not registered. Do not plan around them.

What does work is extracting less at the source.

Anvil documents three file-disclosure layers, but only two are
registered here — escalate straight from Layer 1 to Layer 3:

- `anvil-file-outline` (Layer 1) — structural outline of an
  `.el` / `.org` / `.md` file, no bodies. Start here on a large
  file.
- `anvil-file-read` (Layer 3) — full read, or `offset`/`limit`
  for one section. It accepts the `file://PATH#L10-40` citation
  URI that Layer 1 emits, which becomes the default range.

Layer 2 (`file-read-snippet`) appears in Anvil's own tool
descriptions but is not registered on this machine. Do not call
it.

HTTP extracts server-side, before the body reaches context:

- `selector` on `anvil-http-fetch` takes a CSS subset (tag,
  `.class`, `#id`) against HTML, typically 20–50× cheaper than
  the full page.
- `json_path` walks a dotted path through JSON, with `[N]` index
  and `[*]` wildcard.
- `body_mode=auto` (default) spills bodies over 200KB to a temp
  file and returns a head slice plus `body_overflow_path`.
- A no-match still returns the full body with
  `extract_miss: true` — check that flag before you trust an
  empty-looking result.

Do not treat an outline or a selector hit as the only source of
truth for legal, financial, safety-critical, or exact numeric
work. Read the full range before making claims that depend on
exact wording or values.
