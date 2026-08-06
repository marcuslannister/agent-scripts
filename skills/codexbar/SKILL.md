---
name: codexbar
description: "AI service usage/quota via CodexBar CLI: Codex/OpenAI, Claude, Kimi and other provider limits, credits, reset times."
---

# CodexBar

Use this when asked about AI subscription usage, rate limits, remaining credits, or "how much Codex/Claude/Kimi do I have left".

## CLI

- Binary: `codexbar` (Homebrew)
- Default invocation honors the in-app provider toggles:

```bash
codexbar usage
codexbar usage --format json
```

- Specific provider (`--provider` accepts codex, claude, kimi, gemini, copilot, cursor, openrouter, and many more — see `codexbar --help`):

```bash
codexbar usage --provider codex --json
codexbar usage --provider claude --json
```

- Multiple accounts: `--account <label>`, `--account-index <n>`, or `--all-accounts` (single provider only).

## Auth model

Provider fetches ride existing sessions — OAuth caches, CLI credentials, or browser cookies. No secrets are passed on the command line.

- Codex: OpenAI web dashboard via oauth; falls back to Codex CLI.
- Claude: claude.ai API via browser session cookie; falls back to Claude CLI. "No Claude session key found in browser cookies" means log in to claude.ai in a supported browser (or rely on the CLI fallback).
- Token-based providers read the CodexBar config file.

## Interpreting output

- Errors for providers that were never configured are noise, not failures — only report providers the user actually uses.
- Report percentage left, pace vs. expected, and reset time; the pace line ("in deficit"/"in reserve") is the actionable bit.
