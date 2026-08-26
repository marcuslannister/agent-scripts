# Git

Read this before any commit, branch change, or repository move.
Push authority and destructive-operation limits are in the root `AGENTS.MD`.

## Where to work

- Cwd inside a repository: work there. No sibling checkout unless asked.
- Cwd outside a repository: freeform. Choose a sensible folder and say the path before edits. A worktree is okay if useful.
- `~/Projects` holds intentional same-repo checkouts. They are user-managed, not scratch space.
- No CLI `git worktree` unless asked. If the tree is dirty, the branch is wrong, or the move is awkward: ask.

## Branches

- A branch change needs user consent or authorization from a user-invoked workflow.
- `land` and `ship` authorize the branch changes and the push that they need.
- End the task in the checkout and branch the user expects to see.

## Commits

- Conventional Commits: `feat|fix|refactor|build|ci|chore|docs|style|perf|test`.
- No amend unless asked.
- Small reviewable edits. No repo-wide search/replace scripts.
- Preserve contributor credit: put `Co-authored-by: Name <email>` in the commit body, taken from the PR commit author.

## Shared trees

- Unknown changes in the tree mean another agent is working. Continue, and touch only your own scope. On conflict or any other problem: stop and ask.
