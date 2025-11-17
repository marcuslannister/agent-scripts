# TOOLS

Edit guidance: keep the actual tool list inside the `<tools></tools>` block below so downstream AGENTS syncs can copy the block contents verbatim (without wrapping twice).

<tools>
- `runner`: Bash shim that routes every command through Bun guardrails (timeouts, git policy, safe deletes).
- `git` / `bin/git`: Git shim that forces git through the guardrails; use `./git --help` to inspect.
- `scripts/committer`: Stages the files you list and creates the commit safely.
- `scripts/docs-list.ts`: Walks `docs/`, enforces front-matter, prints summaries; run `./runner tsx scripts/docs-list.ts`.
- `scripts/browser-tools.ts`: Chrome helper for remote control/screenshot/eval; run `./runner ts-node scripts/browser-tools.ts --help`.
- `scripts/runner.ts`: Bun implementation backing `runner`; run `./runner bun scripts/runner.ts --help`.
- `bin/sleep`: Sleep shim that enforces the 30s ceiling; run `./bin/sleep --help`.
- `xcp`: Xcode project/workspace helper; run `./runner xcp --help`.
- `oracle`: CLI to bundle prompt + files for another AI; run `npx -y @steipete/oracle --help` (or via runner).
- `mcporter`: MCP launcher for any registered MCP server; run `./runner npx mcporter`.
- `iterm`: Full TTY terminal via MCP; run `./runner npx mcporter iterm`.
- `firecrawl`: MCP-powered site fetcher to Markdown; run `./runner npx mcporter firecrawl`.
- `XcodeBuildMCP`: MCP wrapper around Xcode tooling; run `./runner npx mcporter XcodeBuildMCP`.
- `gh`: GitHub CLI for PRs, CI logs, releases, repo queries; run `./runner gh help`.
</tools>
