[shared]
# AGENTS.MD

Repo copies of this file wrap the shared content in `[shared]…[/shared]` and the tool list in `<tools>…</tools>`. Those tagged blocks must stay in sync across repos; anything outside them is repo-local—feel free to add project-specific notes there.

READ ~/Projects/agent-scripts/{AGENTS.MD,TOOLS.MD} BEFORE ANYTHING (skip if files missing).

Peter (@steipete) owns this project. Say hi when you start!

## General Guardrails

### Intake & Scoping
- Open the local agent instructions plus any `docs:list` summaries at the start of every session. Re-run those helpers whenever you suspect the docs may have changed.
- Review any referenced tmux panes, CI logs, or failing command transcripts so you understand the most recent context before writing code.

### Tooling & Command Wrappers
- Use the command wrappers provided by the workspace (`./runner …`, `scripts/committer`, `pnpm mcp:*`, etc.). Skip them only for trivial read-only shell commands if that’s explicitly allowed.
- Run all commands through `./runner <command>` to keep timeout guardrails active; skip the wrapper only for non-destructive file inspection (`rg`, `sed`, `ls`, `find`, `cat`, `tmux`, etc.). This includes tests, dev servers, package scripts, and the allowed git commands (`git status`, `git diff`, `git push`). Runner will nudge you into tmux if a job runs long. Whenever you issue a direct CLI call through the harness (any `shell` invocation that bypasses `./runner`), set `timeout_ms` ≥ 60000 so it matches runner’s breathing room—the default 10 s timeout will kill real work before guardrails intervene.
- Stick to the package manager and runtime mandated by the repo (pnpm-only, bun-only, swift-only, go-only, etc.). Never swap in alternatives without approval.
- When editing shared guardrail scripts (runners, committer helpers, browser tools, etc.), mirror the same change back into the `agent-scripts` folder so the canonical copy stays current.
- Ask the user before adding dependencies, changing build tooling, or altering project-wide configuration.
- When discussing dependencies, always provide a GitHub URL.
- Keep the project’s `AGENTS.MD` `<tools></tools>` block in sync with the full tool list from `TOOLS.MD` so downstream repos get the latest tool descriptions.

### tmux & Long Tasks
- Run any command that could hang (tests, servers, log streams, browser automation) inside tmux using the repository’s preferred entry point.
- Even inside tmux, no single command should run longer than 10 minutes—treat anything past that as a hang and investigate a faster path.
- `while tmux …` loops are forbidden; no `tmux has-session` polling. Fire the job, use `sleep` sparingly if you must wait, and call tmux directly (attach/logs/kill) for follow-ups. Skip `tmux wait-for`; let sessions exit so hangs stay visible.
- Do not wrap tmux commands in infinite polling loops. Run the job, sleep briefly (≤30 s), capture output, and surface status at least once per minute.
- Document which sessions you create and clean them up when they are no longer needed unless the workflow explicitly calls for persistent watchers.

### Build, Test & Verification
- Before handing off work, run the full “green gate” for that repo (lint, type-check, tests, doc scripts, etc.). Follow the same command set humans run—no ad-hoc shortcuts.
- Leave existing watchers running unless the owner tells you to stop them; keep their tmux panes healthy if you started them.
- Treat every bug fix as a chance to add or extend automated tests that prove the behavior.
- When someone asks to “fix CI,” use the GitHub CLI (`gh`) to inspect, rerun, and unblock failing workflows on GitHub until they are green.

### Code Quality & Naming
- Refactor in place. Never create duplicate files with suffixes such as “V2”, “New”, or “Fixed”; update the canonical file and remove obsolete paths entirely.
- Favor strict typing: avoid `any`, untyped dictionaries, or generic type erasure unless absolutely required. Prefer concrete structs/enums and mark public concurrency surfaces appropriately.
- Keep files at a manageable size. When a file grows unwieldy, extract helpers or new modules instead of letting it bloat.
- Keep every file under 500 lines of code; split into helpers/modules well before hitting the limit.
- Match the repo’s established style (commit conventions, formatting tools, component patterns, etc.) by studying existing code before introducing new patterns.

### Git, Commits & Releases
- Invoke git through the provided wrappers, especially for status, diffs, and commits. Only commit or push when the user asks you to do so.
- To resolve a rebase, `git add`/`git commit` is allowed.
- Follow the documented release or deployment checklists instead of inventing new steps.
- Do not delete or rename unfamiliar files without double-checking with the user or the repo instructions.

### Documentation & Knowledge Capture
- Update existing docs whenever your change affects them, including front-matter metadata if the repo’s `docs:list` tooling depends on it.
- Whenever doing a large refactor, track work in `docs/refactor/<title><date>.md`, update it as you go, and delete it when the work is finished.
- Only create new documentation when the user or local instructions explicitly request it; otherwise, edit the canonical file in place.
- When you uncover a reproducible tooling or CI issue, record the repro steps and workaround in the designated troubleshooting doc for that repo.

### Troubleshooting & Observability
- Design workflows so they are observable without constant babysitting: use tmux panes, CI logs, log-tail scripts, MCP/browser helpers, and similar tooling to surface progress.
- If you get stuck, consult external references (web search, official docs, Stack Overflow, etc.) before escalating, and record any insights you find for the next agent.
- Keep any polling or progress loops bounded to protect hang detectors and make it obvious when something stalls.

### Stack-Specific Reminders
- Start background builders or watchers using the automation provided by the repo (daemon scripts, tmux-based dev servers, etc.) instead of running binaries directly.
- Use the official CLI wrappers for browser automation, screenshotting, or MCP interactions rather than crafting new ad-hoc scripts.
- Respect each workspace’s testing cadence (e.g., always running the main `check` script after edits, never launching forbidden dev servers, keeping replies concise when requested).

## Swift Projects
- Kick off the workspace’s build daemon or helper before running any Swift CLI or app; rely on the provided wrapper to rebuild targets automatically instead of launching stale binaries.
- Validate changes with `swift build` and the relevant filtered test suites, documenting any compiler crashes and rewriting problematic constructs immediately so the suite can keep running.
- Keep concurrency annotations (`Sendable`, actors, structured tasks) accurate and prefer static imports over dynamic runtime lookups that break ahead-of-time compilation.
- Avoid editing derived artifacts or generated bundles directly—adjust the sources and let the build pipeline regenerate outputs.
- When encountering toolchain instability, capture the repro steps in the designated troubleshooting doc and note any required cache cleans (DerivedData, SwiftPM caches) you perform.

## TypeScript Projects
- Use the package manager declared by the workspace (often `pnpm` or `bun`) and run every command through the same wrapper humans use; do not substitute `npm`/`yarn` or bypass the runner.
- Start each session by running the repo’s doc-index script (commonly a `docs:list` helper), then keep required watchers (`lint:watch`, `test:watch`, dev servers) running inside tmux unless told otherwise.
- Treat `lint`, `typecheck`, and `test` commands (e.g., `pnpm run check`, `bun run typecheck`) as mandatory gates before handing off work; surface any failures with their exact command output.
- Maintain strict typing—avoid `any`, prefer utility helpers already provided by the repo, and keep shared guardrail scripts (runner, committer, browser helpers) consistent by syncing back to `agent-scripts` when they change.
- When editing UI code, follow the established component patterns (Tailwind via helper utilities, TanStack Query for data flow, etc.) and keep files under the preferred size limit by extracting helpers proactively.

Keep this master file up to date as you notice new rules that recur across repositories, and reflect those updates back into every workspace’s local guardrail documents.

## Tools

### runner / bin/runner / scripts/runner.ts
- `runner` is the Bash entry point that routes commands through `bin/runner` (compiled from `scripts/runner.ts`) to enforce timeouts, git policy, and trash-safe deletes. Rebuild `bin/runner` via `bun build scripts/runner.ts --compile --outfile bin/runner`.

### git / bin/git / scripts/git-policy.ts
- Git shim that analyzes invocations and enforces guardrails; call it via `./git` (which wraps runner) and consult `scripts/git-policy.ts` for the rules.

### scripts/committer
- Commit helper that stages exactly the files you list and creates the commit; required instead of direct `git add`/`git commit`.

### bin/docs-list / scripts/docs-list.ts
- `bin/docs-list` walks `docs/`, enforces front-matter, and prints summaries; rebuild via `bun build scripts/docs-list.ts --compile --outfile bin/docs-list`. Edit `scripts/docs-list.ts` before rebuilding.

### bin/browser-tools / scripts/browser-tools.ts
- Compiled Chrome helper for remote control/screenshot/eval; use `bin/browser-tools --help`. Edit `scripts/browser-tools.ts` before rebuilding.

### bin/sleep
- Sleep shim capped at 30 seconds; run `bin/sleep --help`.

### xcp
- Xcode project/workspace helper for managing targets, groups, files, build settings, and assets; run `xcp --help`.

### xcodegen
- Generates Xcode projects from YAML specs; run `xcodegen --help`.

### lldb
- Use `lldb` inside tmux to debug native apps; attach to the running app to inspect state.

### axe
- Simulator automation CLI for describing UI (`axe describe-ui --udid …`), tapping (`axe tap --udid … -x … -y …`), typing, and hardware buttons. Use `axe list-simulators` to enumerate devices.

### oracle
- AI reviewer CLI; run `npx -y @steipete/oracle --help` before invoking.

### mcporter / iterm / firecrawl / XcodeBuildMCP
- MCP launcher (`npx mcporter`) plus specific endpoints: `iterm` for TTY control, `firecrawl` for site-to-Markdown fetching, `XcodeBuildMCP` for Xcode tooling. Each is invoked via `npx mcporter <tool>`.

### gh
- GitHub CLI for PRs, CI logs, releases, and repo queries; run `gh help`.

### AXe (Simulator automation)
- - Whenever you need to interact with the iOS Simulator (taps, typing, hardware buttons), use AXe instead of AppleScript or UI scripting.
- - Describe the current screen: `axe describe-ui --udid <sim-udid>` (find UDID via `xcrun simctl list`).
- - Drive interactions with that UDID: tap via `axe tap --udid <udid> -x <x> -y <y>`, type via `axe type --udid <udid> "Some text"`, lock via `axe button --udid <udid> lock`.
- - `axe list-simulators` shows available devices if you’re not already targeting a booted simulator.
