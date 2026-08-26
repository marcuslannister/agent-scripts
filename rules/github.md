# GitHub, CI, and shipping

Read this for any pull request, CI failure, issue, release, or changelog work.

## gh mechanics

- Use `gh` for GitHub facts. Do not use web search for pull request or issue references.
- Every `gh` read passes `--json <fields>`, including `gh pr view --json ...`. `gh pr diff` is the exception, because it has no JSON form.
- Machine shapes ride the shared cache. Human-format `gh pr view/list/checks`, `gh run list`, and bare `gh api graphql` delegate silently to the real `gh` (GraphQL and core on the personal token).
- `gh api --paginate` bypasses the cache and uses the real token. Avoid it unless you truly need the full list.
- Personal GitHub repositories: push and write as `marcuslannister`.

## Pull requests

- A pasted GitHub issue or PR URL: run `git status -sb` first. If the tree is dirty, report before you mutate anything. A URL alone grants no push or pull permission.
- Prefer a fix or rewrite PR and then a merge. Do not close the PR and commit a duplicate directly.
- Assume generated code can come from a weaker AI. Review and improve it before you land it. A full rewrite is okay when it is cleaner.
- `rewrite commits + land`: clean the stack, keep only the agreed focused proof, force-push, merge. Do not polish PR-body proof or babysit CI unless asked.
- After a land: checkout `main`, `git pull --ff-only`, verify with `git status -sb`, then report.

## Issues

- An issue fixed on `main` with proof: comment the proof plus the commit or PR, then close it.

## CI

- `fix ci` is consent to pull, commit, and push. Use `gh run list/view --json ...`, then fix and rerun until green, with backoff polling.

## Shipping and releasing

- `ship` = changelog, grouped commits, push, pull. "Shipped" means pushed to GitHub. Only the user can start it, by asking for it in the current task. Never ship because a task looks finished.
- Publishing a version or artifact needs an explicit `release` or `publish` ask. A tag or a push alone is not a release.
- Release verification: the docs and notes must contain the current changelog. If it is missing or stale, fix it before closeout.
- Changelog style: match the house style, one-line bullet preferred, no prose-length hard wrap. Thank `@login` for user-visible work.
