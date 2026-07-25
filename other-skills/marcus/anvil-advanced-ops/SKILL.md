---
name: anvil-advanced-ops
description: "Advanced Anvil MCP workflows: org-mode section moves/refile, dispatching heavy Emacs ops (tangles, byte-compile, multi-MB scans) to the worker pool, anvil-cron scheduled tasks, and compressing long shell/context output. Use when doing org-mode editing, long-running Emacs operations, recurring anvil-cron tasks, or when command/tool output is long enough to need compression."
---

## org-mode

For section moves, refile, splits, or reading a single heading
from a large org file, use `anvil-org-*` tools instead of
Read+Write. They are 10–20× cheaper in tokens.

- `anvil-org-read-headline` — read a single subtree
- `anvil-org-read-outline` — outline view without bodies
- `anvil-org-edit-body` / `anvil-org-rename-headline` /
  `anvil-org-update-todo-state` — targeted org edits

## Heavy operations — worker dispatch

Long-running Emacs ops (large tangles, byte-compile, multi-MB
org scans, full-tree searches) must not run on the main daemon —
they block every other tool call. Dispatch them through the
worker pool instead.

- Elisp called from inside Anvil: prefer `anvil-worker-call` over
  raw `eval` for anything that may exceed ~1s.
- If the worker is registered as its own MCP server (see README
  "Optional: register the worker pool too"), heavy `eval` calls
  should target `mcp__anvil-worker__eval` directly so the main
  session stays responsive.

Symptom that you should have used the worker: the main MCP
session stops accepting tool calls for several seconds.

## Scheduled tasks (cron)

If `anvil-cron` tasks are configured (lint, health checks, batch
indexers, etc.), do not re-implement their work ad hoc. Inspect
and trigger them through the cron MCP tools:

- `anvil-cron-list` — what tasks exist and their schedules
- `anvil-cron-status` — last run time, status, recent failures
- `anvil-cron-run` — fire a registered task on demand

Before writing a new ad-hoc script, check `anvil-cron-list` —
the job may already be defined.

## Context and output compression

When command output or retrieved context is long, compress it before
feeding it back into the main reasoning loop.

- Use `shell-run` for shell commands whose stdout can be filtered
  automatically. It returns compressed stdout plus a `tee-id`; recover
  the raw output with `shell-tee-get` only when the compressed view is
  insufficient.
- Use `context-compress` for non-shell text: API JSON, RAG snippets,
  web/article extracts, logs from another tool, diffs, or code
  excerpts. Set `store=true` when the raw text may be needed later;
  recover it with `context-retrieve` and the returned `ccr-id`.
- Use `context-stats` / `shell-gain` to inspect savings instead of
  guessing whether the compression layer is helping.

Do not use compressed views as the only source of truth for legal,
financial, safety-critical, or exact numeric work. Retrieve the raw
context before making claims that depend on exact wording or values.
