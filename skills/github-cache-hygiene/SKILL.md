---
name: github-cache-hygiene
description: Use when GitHub work may hit rate limits, when using gh for issues/PRs/actions, or when a task mentions ghx, gh xcache, gitcrawl, caching, local GitHub mirrors, quota pressure, or many Codex agents.
---

# GitHub Cache Hygiene

Goal: answer common GitHub read questions from gitcrawl and the `gh` shim first, then spend live GitHub API calls only where freshness or writes matter.

## Default Path

Use `gh` normally. On Peter's machines it is expected to be the gitcrawl-backed shim, so supported reads can be answered locally or cached without changing commands.

Prefer these local/cached reads:

```bash
gh search issues "<terms>" -R owner/repo --state open --json number,title,state,url,updatedAt,labels,author
gh search prs "<terms>" -R owner/repo --state open --json number,title,state,url,updatedAt,isDraft,author
gh issue list -R owner/repo --state open --author user --assignee user --label bug --json number,title,url
gh pr list -R owner/repo --state open --author user --label dependencies --json number,title,url
gh issue view 123 -R owner/repo --json number,title,state,body,comments,labels,url
gh pr view 123 -R owner/repo --json number,title,state,body,comments,labels,files,commits,url
gh pr diff 123 -R owner/repo --patch
```

Use exact refs and narrow fields. Avoid broad loops like one `gh issue view` per result when a single `gh search` or `gh issue list --json ...` can answer the first-pass question.

## Freshness

Local answers are good for discovery, duplicate search, old thread review, author/label triage, and "is there likely already an issue/PR?" checks.

Use a live call when:

- writing, commenting, closing, merging, rerunning, or editing
- checking final current state before a maintainer action
- verifying CI status after a push
- the local result is missing or obviously stale
- the user asks for latest/live state

After a write, do one targeted readback, not a broad rescan.

## XCache

Inspect cache behavior when rate limits are suspected:

```bash
gh xcache stats
gh xcache keys
gh xcache gc
```

Use `gh xcache flush` only when a stale cached fallback read is misleading a decision.

For local-only proof, temporarily make the backend unavailable for a single command:

```bash
GITCRAWL_GH_PATH=/tmp/no-real-gh gh search issues "<terms>" -R owner/repo --json number,title,url
```

## Agent Etiquette

Batch questions by repo and state. Reuse data already printed in the session. Back off CI polling; inspect logs only for failing runs or the exact run under review. Do not bypass the shim with `/opt/homebrew/opt/gh/bin/gh` unless diagnosing the shim itself.
