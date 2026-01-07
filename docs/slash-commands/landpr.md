---
summary: 'Slash command: /landpr prompt template.'
read_when:
  - Landing a PR end-to-end (rebase temp branch, changelog, gate, merge).
---
# /landpr

Land PR: rebase onto temp branch from main, fix+tests+changelog, run pnpm lint && pnpm build && pnpm test before commit, commit via committer, fast‑forward main, push, close PR, delete temp branch.
