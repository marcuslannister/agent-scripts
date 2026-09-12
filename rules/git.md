# Git

## Authorization

- Task completion does not authorize commits, pushes, tags, or publication. Leave changes uncommitted unless the user authorizes these actions.
- Push only when the user asks in this task or invokes a workflow that explicitly pushes.
- This rule applies to every repository. Repository rules can define push steps, but cannot authorize a push.
- Rewrite published history only when the user explicitly requests that specific rewrite.
- This includes force-push, rebase onto a pushed base, `filter-branch`, and `filter-repo`.
- `reset --hard`, `clean`, and `restore` each require an explicit user request every time.
- Delete files only within the task scope. Never delete or overwrite unknown or unrelated user data.

## Where to work

- Inside a repository, work there. Create a sibling checkout or worktree only when asked.
- Outside a repository, choose a suitable folder. State its path before editing. You may create a worktree without asking.
- Checkouts under `~/Projects` belong to the user. Do not use them as temporary storage.
- Continue if unrelated changes do not overlap your task. Change only your own files.
- Stop and ask if changes overlap, the branch is wrong, or a repository move is unclear.

## Branches

- Change branches only with user consent or permission from a user-invoked workflow.
- `land` and `ship` authorize the branch changes and pushes that they require.
- Finish in the checkout and branch the user expects.

## Commits

- Use Conventional Commits: `feat|fix|refactor|build|ci|chore|docs|style|perf|test`.
- Amend only when asked.
- Keep edits small and easy to review. Do not run repository-wide search-and-replace scripts.
- Apply [artifact privacy](~/.claude/rules/artifacts.md).
