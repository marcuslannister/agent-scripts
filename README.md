# Agent Scripts

This folder collects the Sweetistics guardrail helpers so they are easy to reuse in other repos or share during onboarding. Everything here is copied verbatim from `/Users/steipete/Projects/sweetistics` on 2025-11-08 unless otherwise noted.

## Syncing With Other Repos
- Treat this repo as the canonical mirror for the shared guardrail helpers. Whenever you edit `runner`, `scripts/runner.ts`, `bin/git`, `scripts/git-policy.ts`, `scripts/committer`, or `scripts/docs-list.ts` in any repo, copy the change here and then back out to every other repo that carries the same helpers so they stay byte-identical.
- When someone says “sync agent scripts,” pull the latest changes here, ensure downstream repos have the pointer-style `AGENTS.MD`, copy any helper updates into place, and reconcile differences before moving on.
- Keep every file dependency-free and portable: the scripts must run in isolation across repos. Do not add `tsconfig` path aliases, shared source folders, or any other Sweetistics-specific imports—inline tiny helpers or duplicate the minimum code needed so the mirror stays self-contained.

## Pointer-Style AGENTS
- Shared guardrail text now lives only inside this repo: `AGENTS.MD` (shared rules + tool list).
- Every consuming repo’s `AGENTS.MD` is reduced to the pointer line `READ ~/Projects/agent-scripts/AGENTS.MD BEFORE ANYTHING (skip if missing).` Place repo-specific rules **after** that line if they’re truly needed.
- Do **not** copy the `[shared]` or `<tools>` blocks into other repos anymore. Instead, keep this repo updated and have downstream workspaces re-read `AGENTS.MD` when starting work.
- When updating the shared instructions, edit `agent-scripts/AGENTS.MD`, mirror the change into `~/AGENTS.MD` (Codex global), and let downstream repos continue referencing the pointer.

## Runner Shim (`runner`, `scripts/runner.ts`)
- **What it is:** `runner` is the Bash entry point that forces commands through Bun and `scripts/runner.ts`. The Bun runner enforces timeout tiers, intercepts risky commands (git/rm/find), auto-prompts for tmux handoffs, and ensures cleanup logs stay consistent across repos.
- **Execution & timeout tiers:** Default timeout is 5 minutes, but the wrapper auto-detects lint/test/build keywords to grant 20 minute “extended,” 25 minute “long,” or 30 minute “lint” headroom. Integration specs and single-test flags are parsed so focused runs stay fast while full suites get extra time (`scripts/runner.ts`:40-214).
- **Deletion guardrails:** Before spawning the real command, the runner intercepts `find -delete`, `rm`, and `git rm`, moves targets into macOS Trash (or `trash-cli`) and only stages the removals via `git rm --cached` once the files are safe. Cross-device copies fall back to `cp` + `rm` so nothing is lost even when `.Trash` lives on another volume (`scripts/runner.ts`:562-1099).
- **Git policy enforcement:** Every invocation is analyzed with `scripts/git-policy.ts`. Direct `git add`/`git commit` calls are blocked in favor of `./scripts/committer`, destructive subcommands (`reset`, `checkout`, etc.) and guarded ones (`push`, `pull`, `rebase`) require `RUNNER_THE_USER_GAVE_ME_CONSENT=1`, and rebases refuse to run until the user explicitly types “rebase” in chat (`scripts/runner.ts`:568-648, `scripts/git-policy.ts`).
- **Signal handling & tmux nudges:** Child processes inherit stdin while stdout/stderr are piped so the runner can append completion/timing metadata. It forwards SIGINT/SIGTERM, kills over-timeout jobs with SIGTERM→SIGKILL escalation, and emits reminders to move long-lived work into tmux sessions when `RUNNER_TMUX`/`TMUX` are set (`scripts/runner.ts`:400-520).
- **Binary build:** `bin/runner` is the compiled Bun binary that `./runner` delegates to. Rebuild it after editing `scripts/runner.ts` via `bun build scripts/runner.ts --compile --outfile bin/runner` (run inside this repo with Bun installed).
- **AGENTS.MD rules:**  
  - “Run all commands through `./runner <command>` ... skip only for read-only inspection tools.” (AGENTS.MD:50)  
  - “When I type ‘rebase,’ … keep using `./runner git …` (or `./git …`) so the guardrails stay active.” (AGENTS.MD:189)  
  - “When you run the allowed git commands, invoke them through the wrapper (e.g., `./runner git status -sb`).” (AGENTS.MD:190)

## Git Shim (`git`, `bin/git`, `scripts/git-policy.ts`)
- **What it is:** Bun-based drop-in replacement for git that analyzes the invocation, blocks destructive subcommands, and requires either the committer helper or explicit consent environment variables. `scripts/git-policy.ts` houses the heuristics.
- **AGENTS.MD rules:**  
  - “IMPORTANT! ALL git commands are forbidden ... the only git CLI commands you may run are `git status`, `git diff`, and `git log`; run `git push` only when I explicitly ask for it.” (AGENTS.MD:181-184)  
  - “When I type ‘rebase,’ treat it as consent ... Keep using `./runner git …` (or `./git …` if you absolutely must) so the guardrails stay active.” (AGENTS.MD:189)

## Committer Helper (`scripts/committer`)
- **What it is:** Bash helper that stages exactly the files you list, enforces non-empty commit messages, and creates the commit (used because direct `git add`/`git commit` is blocked).
- **AGENTS.MD rules:**  
  - “IMPORTANT! To create a commit, use `./scripts/committer "your commit message" "path/to/file1" "path/to/file2"` ... never run `git add` yourself.” (AGENTS.MD:192)

## Docs Lister (`scripts/docs-list.ts`)
- **What it is:** tsx script that walks `docs/`, enforces front-matter (`summary`, `read_when`), and prints the summaries surfaced by `pnpm run docs:list`. Other repos can wire the same command into their onboarding flow.
- **Binary build:** `bin/docs-list` is the compiled Bun CLI; regenerate it after editing `scripts/docs-list.ts` via `bun build scripts/docs-list.ts --compile --outfile bin/docs-list`.
- **AGENTS.MD rules:**  
  - “Non-negotiable: run `pnpm run docs:list`, read the summaries, and open the referenced rule files before you write a single line of code.” (AGENTS.MD:72)  
  - “Start every session with `pnpm run docs:list` ... keep the relevant docs open while you implement.” (AGENTS.MD:77)  
  - “Add `read_when` hints to key docs so `pnpm docs:list` surfaces them when the topic is relevant.” (AGENTS.MD:81)

## Browser Tools (`bin/browser-tools`)
- **What it is:** A standalone Chrome helper inspired by Mario Zechner’s [“What if you don’t need MCP?”](https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/) article. It launches/inspects DevTools-enabled Chrome profiles, pastes prompts, captures screenshots, and kills stray helper processes without needing the full Oracle CLI.
- **Usage:** Prefer the compiled binary: `bin/browser-tools --help`. Common commands include `start --profile`, `nav <url>`, `eval '<js>'`, `screenshot`, `search --content "<query>"`, `content <url>`, `inspect`, and `kill --all --force`.
- **Rebuilding:** The binary is not tracked in git. Re-generate it with `./runner bun build scripts/browser-tools.ts --compile --target bun --outfile bin/browser-tools` (requires Bun) and leave transient `node_modules`/`package.json` out of the repo.
- **Portability:** The tool has zero repo-specific imports. Copy the script or the binary into other automation projects as needed and keep this copy in sync with downstream forks. It detects Chrome sessions launched via `--remote-debugging-port` **and** `--remote-debugging-pipe`, so list/kill works for both styles.

## Sync Expectations
- This repository is the canonical mirror for the guardrail helpers used in mcporter and other Sweetistics projects. Whenever you edit `runner`, `scripts/runner.ts`, `scripts/committer`, `bin/git`, `scripts/git-policy.ts`, `scripts/docs-list.ts`, or related guardrail files in another repo, copy the changes back here immediately (and vice versa) so the code stays byte-identical.
- When someone asks to “sync agent scripts,” update this repo, compare it against the active project, and reconcile differences in both directions before continuing.

## @steipete Agent Instructions (pointer workflow)
- The only full copies of the guardrails are `agent-scripts/AGENTS.MD` and `~/AGENTS.MD`. Downstream repos should contain the pointer line plus any repo-local additions.
- During a sync sweep: pull latest `agent-scripts`, ensure each target repo’s `AGENTS.MD` contains the pointer line at the top, append any repo-local notes beneath it, and update the helper scripts as needed.
- If a repo needs custom instructions, clearly separate them from the pointer so future sweeps don’t overwrite local content.
- For submodules (Peekaboo/*), repeat the pointer check inside each subrepo, push those changes, then bump submodule SHAs in the parent repo.
- Skip experimental repos (e.g., `poltergeist-pitui`) unless explicitly requested.
