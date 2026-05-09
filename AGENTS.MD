# AGENTS.MD

Work style: telegraph; noun-phrases ok; drop grammar; min tokens.
Codex CLI output: avoid Markdown tables by default; they render poorly there. Use short bullets or `key: value` lines instead. Only use a table when explicitly requested.

## Core

- Contact: Peter Steinberger (@steipete, steipete@gmail.com).
- Workspace: `~/Projects`. Missing steipete repo: clone `https://github.com/steipete/<repo>.git`.
- 3rd-party/OSS (non-steipete): clone under `~/Projects/oss`.
- Files: repo or `~/Projects/agent-scripts`.
- "Make a note" => edit `AGENTS.MD` (shortcut; not a blocker). Ignore `CLAUDE.md`.
- Skills are canonical for tool-specific workflows. Keep this file as routing + hard rules.
- Read `~/Projects/agent-scripts/tools.md` when the tool catalog matters.

## Routing

- PRs/issues/reviews: use `gh`; deep review => `$github-deep-review`; queue triage => `$github-project-triage`.
- Browser in Codex CLI: use `$browser-use` / mcporter `chrome-devtools` for existing Chrome. Bundled Browser plugin is Codex-app-only. No AppleScript/osascript fallback.
- MacBook / Mac Studio: use `$remote-mac`.
- Codex debugging: use `$codex-debugging`.
- Screenshots/assets: use newest PNG in `~/Desktop` or `~/Downloads`; verify it is the right UI before replacing.
- Data archives: prefer local archives before web/API; check freshness for current questions.
- Discord: `$discrawl`.
- Slack archive: `$slacrawl`.
- WhatsApp: `$whatsapp` first; explicit repo/tool work => `$wacrawl` or `$wacli`.
- Notion: `$notcrawl`.
- iMessage/SMS: `$imsg`; send only when explicitly asked.
- Beeper: `$beeper`.
- X/Twitter: `$birdclaw`; live X API => `$xurl`.
- Google services CLI: `$gog` when connectors are insufficient.
- Obsidian: `$obsidian`; default vault `obsidian`.
- Secrets: check `~/.profile` first; `op` only via `$one-password`.

## Project Defaults

- Need upstream file: stage in `/tmp/`, then cherry-pick; never overwrite tracked files.
- Bugs: add regression test when it fits.
- Keep files <~500 LOC; split/refactor as needed.
- Use repo package manager/runtime; no swaps without approval.
- Docs: read repo docs before coding; update docs/changelog for user-visible behavior changes.
- New deps: quick health check for recent releases/commits/adoption.
- Subagents: read `docs/subagent.md`.
- Editor: `code <path>`.
- Slash cmds: `~/.codex/prompts/`.

## PR / CI

- PR refs: use `gh pr view/diff`, not web search.
- CI: `gh run list/view`; rerun/fix until green when asked.
- Replies: cite fix + file/line; resolve threads only after fix lands.
- User-facing fixes/landed PRs: changelog unless pure test/internal.
- When merging contributor PRs: thank contributor in `CHANGELOG.md`.

## Runtime Safety

- Use Codex background for long jobs; tmux only for interactive/persistent processes.
- zsh: don't use `status` as a variable.
- OpenClaw Gateway: Peter runs it via pm2 watcher. Never start/load via launchd/LaunchAgent. Do not run `openclaw gateway start/install` or `launchctl bootstrap` for `ai.openclaw.gateway`; if gateway is down, ask before touching pm2.
- 1Password/op: never run `op` directly in a normal shell. Use `$one-password`. No broad vault/item enumeration, no secret output.

## Git

- Safe by default: `git status/diff/log`.
- Push only when user asks.
- End in visible checkout/branch user expects.
- Branch changes require user consent.
- Destructive ops forbidden unless explicit: `reset --hard`, `clean`, `restore`, `rm`, etc.
- Remotes under `~/Projects`: prefer HTTPS; flip SSH -> HTTPS before pull/push.
- Commit helper on PATH: `committer` (bash). Prefer it; if repo has `./scripts/committer`, use that.
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Don't delete/rename unexpected stuff; stop + ask.
- No repo-wide S/R scripts; keep edits small/reviewable.
- If user types a command ("pull and push"), that's consent for that command.
- No amend unless asked.
- Unrecognized changes: assume other agent; keep going; focus your changes. If it causes issues, stop + ask user.

## Locations

- Blog repo: `~/Projects/steipete.me`.
- Private ops/runbooks: `~/Projects/manager/docs/`.
- Codex limits tracking: `~/Documents/steipete/codex limits.md`.
- Sparkle keys: `~/Library/CloudStorage/Dropbox/Backup/Sparkle`.
