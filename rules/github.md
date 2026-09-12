# GitHub, CI, and shipping

## GitHub commands

- Use `gh` for GitHub facts. Do not use web search for pull request or issue references.
- Use `--json <fields>` for every `gh` read. Exception: `gh pr diff` has no JSON output.
- The shared cache handles machine-readable output.
- Human-format `gh pr view/list/checks` and `gh run list` bypass the cache. So does bare `gh api graphql`.
- GraphQL and core requests use the personal token.
- `gh api --paginate` bypasses the cache and uses the real token. Use it only when you need the full list.
- For personal repositories, push and write with the repository owner's account. Check the active account before writing.

## Pull requests

- For a pasted GitHub issue or PR URL, first run `git status -sb`.
- If the tree is dirty, report this before making changes. A URL alone does not authorize a push or pull.
- Prefer a fix or rewrite PR, then merge it. Do not close the PR and commit a duplicate directly.
- Review and improve generated code before merging it. Rewrite it fully if this makes it simpler.
- `rewrite commits + land`: simplify the commit stack. Keep only the agreed focused proof. Force-push, then merge.
- For that workflow, refine PR-body proof or monitor CI only when asked.
- After `land`, check out `main`. Run `git pull --ff-only`, then `git status -sb`. Report the result.

## Issues and CI

- If an issue is fixed on `main` with proof, comment with the proof and commit or PR. Then close it.
- `fix ci` authorizes pull, commit, and push. Use `gh run list/view --json ...`.
- Fix and rerun until CI passes. Increase the wait between status checks.

## Shipping and releases

- Only the user can start `ship`, by asking in the current task. Task completion does not authorize shipping.
- `ship` means: update the changelog, make grouped commits, push, then pull. Report "shipped" only after the push to GitHub.
- Publish a version or artifact only after an explicit `release` or `publish` request. A tag or push is not a release.
- Before finishing a release, check that the docs and notes contain the current changelog. Fix missing or stale content.
- Match the existing changelog style. Prefer one-line bullets. Do not wrap prose manually. Thank `@login` for user-visible work.
