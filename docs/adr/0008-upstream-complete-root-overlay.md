# Keep an upstream-complete root overlay

The repository root keeps every path from `steipete/agent-scripts:main` at its upstream path while it also permits local additions and committed modifications. We chose this overlay instead of a separate vendored tree so upstream files remain discoverable in their normal locations; local replacements do not permit deletion of the upstream path, and offline verification checks the recorded upstream commit.

## Amendment: excluded paths

A path in the `excluded` list of `agent-tooling/upstream-overlay.json` is not required and is not restored. Use this list only when a file moved to another repo on purpose, so a copy here would compete with the new owner. Example: `AGENTS.MD` moved out of the root (to the `home` repo, then to `global/AGENTS.md`, ADR-0013); an upstream copy at the root would give Codex and Pi this repo's project rules from steipete's file. Every other upstream path stays required.
