# Keep an upstream-complete root overlay

The repository root keeps every path from `steipete/agent-scripts:main` at its upstream path while it also permits local additions and committed modifications. We chose this overlay instead of a separate vendored tree so upstream files remain discoverable in their normal locations; local replacements do not permit deletion of the upstream path, and offline verification checks the recorded upstream commit.
