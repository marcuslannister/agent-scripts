---
summary: 'Index of slash commands (prompts) and where they live.'
read_when:
  - Auditing or updating slash command docs.
---
# Slash Commands

Slash commands are reusable prompt templates that live in `~/.codex/prompts/` (global) and, when present, in repo-local folders (e.g., `.claude/commands/`, `.cursor/commands/`). This folder mirrors the global set so agents can discover and edit them in-repo.

## Available commands
- `/handoff` — Capture current state for the next agent (running sessions, tmux targets, blockers, next steps).
- `/pickup` — Rehydrate context when starting work (status, tmux sessions, CI/PR state).

See the individual files in this directory for details.
