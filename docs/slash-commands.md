---
summary: 'Slash commands (prompts) for Claude integration. Covers custom command setup.'
---
# Slash Commands

Slash commands are reusable prompt templates stored as markdown files that guide agents through complex workflows.

## Locations

### Global Commands
**`~/.codex/prompts/`** - Available across all projects when using Codex/Claude Code

### Project-Local Commands
**`.claude/commands/`** - Repo-specific commands for Claude Code
**`.cursor/commands/`** - Repo-specific commands for Cursor AI

Project-local commands are checked into version control and shared with the team.

## Available Commands

### `/automerge` - Automated PR Review & Merge
**File:** `~/.codex/prompts/automerge.md`

Fully reviews and lands pull requests with comprehensive checks:
- Fetches PR metadata and inline comments via `gh` CLI
- Reviews diffs, validates against modern patterns
- Fixes issues, runs tests, ensures CI passes
- Pushes changes and merges with `gh pr merge --squash --delete-branch`
- Loops until all PRs are green

**Usage:** `/automerge` or `/automerge PR#123 PR#456`

---

### `/build` - Build Validation
**File:** `~/.codex/prompts/build.md`

Runs full Next.js build after fixing lint/type errors:
1. Invokes `/fix` first
2. Runs `pnpm run build`
3. Triages build failures
4. Applies thoughtful fixes (not quick hacks)
5. Reruns until build succeeds

**Usage:** `/build`

---

### `/claude` - Fallback Command Loader
**File:** `~/.codex/prompts/claude.md`

Meta-command that executes unknown slash commands by looking them up in `~/.codex/prompts/`.

**Content:** "If a user enters an unknown slash command, look for a matching file in ~/.codex/prompts/ and execute it."

---

### `/commit` - Selective Commit Helper
**File:** `~/.codex/prompts/commit.md`

Creates commits for your files only, ignoring other dirty files in the repo:
- Runs `git status -sb` to see dirty files
- Identifies which files belong to you
- **Best effort:** Groups changes into logical commits (creates multiple commits if changes don't fit together)
- Commits using `./scripts/committer "type(scope): subject" "file1" "file2"`
- Follows Conventional Commits style
- Never touches teammates' files

**Usage:** `/commit`

**Key rules:**
- Only runs `git status` and `git diff` (no destructive git commands)
- Uses `./scripts/committer` for safe, selective staging
- Respects other agents' work in the same tree
- Will create one or multiple commits depending on what makes logical sense

---

### `/commitgroup` - Group Multiple Commits
**File:** `~/.codex/prompts/commitgroup.md`

Organizes many dirty files into focused, logical commits:
- Lists all dirty files with `git status -sb`
- Groups changes by functional area (features, fixes, refactors)
- Commits each group separately via `./scripts/committer`
- Folds minor formatting into relevant functional groups
- Never reverts or discards edits
- **Leaves new untracked files untouched** — if agents add files during execution, lists them but does not commit them (prevents infinite loops with concurrent agents)

**Usage:** `/commitgroup`

**Best for:** Large refactors or multi-file changes that need atomic commits

**Key rule:** Only commits files that were dirty at the start. Any new files added by other agents are left as-is and noted at the end.

---

### `/cppp` - Commit + Push Everything
**File:** `~/.codex/prompts/cppp.md`

Commits all current changes in sensible groups, then pushes:
- Lists dirty files with `git status -sb`
- Groups by area/feature; never mixes unrelated changes
- Uses `./scripts/committer` for each group (Conventional Commits style)
- After commits are created, pushes branch (`RUNNER_THE_USER_GAVE_ME_CONSENT=1 ./git push`)
- Stops if ownership/scope is unclear or a commit fails

**Usage:** `/cppp`

**Safeguards:**
- No destructive git (no reset/checkout --)
- Respects teammate-unrelated work; leaves their files untouched and reports them
- Aborts if tests are failing unless user explicitly overrules

---

### `/fix` - Run Quality Checks & Fix
**File:** `~/.codex/prompts/fix.md`

Runs `pnpm check` and fixes all failures:
1. Executes `pnpm check` (lint + type-check + tests)
2. Walks failures in priority order
3. Applies precise, correct fixes (no workarounds)
4. Never deletes functionality to satisfy checks
5. Reruns `pnpm check` until green

**Usage:** `/fix`

**Rules:**
- Only uses `git status` and `git diff` for context
- Stops if scope is unclear
- Respects other agents' in-progress work

---

### `/improve` - Post-Ship Retro Helper
**File:** `~/.codex/prompts/improve.md`

Guides a fast retro once a change ships:
- Recaps the shipped work in a single sentence for shared context
- Surfaces the highest-impact improvements to pursue next, with rationale and validation steps
- Flags follow-up docs or tickets and points out missing information to gather first

**Usage:** `/improve`

---

### `/lint` - Lint Fix Task Notes
**File:** `~/.codex/prompts/lint.md`

Task notes from October 11, 2025 with constraints:
- Prioritize Biome lint errors and TypeScript failures
- No destructive git commands
- No file deletion without certainty
- Prefer targeted fixes with clear typing
- Leave unclear areas for teammate

**Note:** This appears to be task-specific notes rather than a reusable command.

---

### `/massageprs` - Continuous PR Maintenance Loop
**File:** `~/.codex/prompts/massageprs.md`

Cycles through all open PRs until simultaneously green:
1. Fetches all PR metadata and comments
2. Uses dedicated worktrees per PR (`git worktree add`)
3. Resolves feedback and failing checks
4. Keeps branches rebased on main
5. Pushes fixes and responds to comments
6. Loops until all PRs pass

**Usage:** `/massageprs`

**Best for:** Maintaining many open PRs during heavy development

---

### `/different` - Reflection: What Would You Do Differently?
**File:** `~/.codex/prompts/different.md`

After reviewing or shipping code, surfaces alternative approaches and improvements:
- Summarizes the implemented solution in one breath
- Lists 3–5 concrete things to change if redoing the work (architecture, DX, tests, perf, naming)
- Highlights the single highest-impact change and why
- Notes missing tests/coverage and quick wins
- Provides a tiny next-action checklist (≤5 items)

**Usage:** `/different`

**Guardrails:**
- Keep feedback actionable and scoped; no rambling
- Avoid rework that conflicts with owner constraints you know about
- Call out unknowns/assumptions explicitly

---

## How to Create Slash Commands

1. **Create a markdown file** in `~/.codex/prompts/`:
   ```bash
   echo "# /mycommand\n\nYour prompt instructions..." > ~/.codex/prompts/mycommand.md
   ```

2. **Use the command** in any Codex/Claude Code session:
```text
   /mycommand
   ```

3. **The agent will execute** the prompt from the file

## Best Practices

- **Be specific:** Include exact commands, safety checks, and exit conditions
- **Document constraints:** No destructive git, coordination rules, scope boundaries
- **Make them reusable:** Avoid task-specific details (dates, ticket numbers)
- **Test them:** Run the slash command to verify it works as expected
- **Version control:** Consider storing project-specific commands in `.claude/commands/` (repo-local)

## Project-Local Commands

For project-specific workflows, you can also create commands in the repo root:

**`.claude/commands/`** - For Claude Code
**`.cursor/commands/`** - For Cursor AI

These are checked into version control and shared with the team.

### This Project's Commands

This repository includes the following commands in both `.claude/commands/` and `.cursor/commands/`:

```bash
.claude/commands/          .cursor/commands/
├── automerge.md          ├── automerge.md
├── build.md              ├── build.md
├── commit.md             ├── commit.md
├── commitgroup.md        ├── commitgroup.md
├── improve.md            ├── improve.md
├── fix.md                ├── fix.md
└── massageprs.md         └── massageprs.md
```

**Available commands:**
- `/automerge` - Automated PR review & merge
- `/build` - Build validation with fixes
- `/commit` - Selective commit helper
- `/commitgroup` - Group multiple commits logically
- `/cppp` - Commit all changes in grouped commits and push
- `/different` - Post-review reflection: what would you change?
- `/improve` - Post-ship retro helper
- `/fix` - Run quality checks & fix all failures
- `/massageprs` - Continuous PR maintenance loop

These commands work identically in both Claude Code and Cursor.
