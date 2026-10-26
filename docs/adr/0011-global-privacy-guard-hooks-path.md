---
status: accepted
---

# Global privacy guard through one hooks path

An installer wrote an absolute home path of another account into `claude-code-settings`, and it reached a public repo. Prose rules could not catch it, because no person or agent wrote that line. No repo had a commit-time check. The fix needed a history rewrite.

The privacy guard runs in every repo on a host through one global `core.hooksPath`. The setting lives in `dotfiles/.gitconfig` as `~/Projects/agent-scripts/hooks` (Git expands the `~`). It is not set by `git config --global`, because home-manager owns `~/.gitconfig` as a symlink into `dotfiles`. It is not set by `setup-agent-instructions.sh` either: that script manages instruction pointers only (ADR-0002, ADR-0010).

A global hooks path makes Git ignore each repo's `.git/hooks`. So `hooks/` holds one dispatcher, linked under each common hook name. The dispatcher runs the guard where it applies, then runs `.git/hooks/<name>` if that file is executable. A repo with its own local `core.hooksPath` (husky, lefthook) overrides the global value and keeps its own hooks. The dispatcher never runs tracked hook files from the repo being committed, because a cloned repo that you do not trust would then run its code on commit. The only repo-specific step is `validate-skills`, which runs only when the repo root is the checkout that holds `hooks/`.

The guard checks only added lines and the commit message. Old hits do not block a commit until someone edits the line. Exceptions go in a per-repo `.privacy-allow` file of path globs. There are no inline markers, because upstream text and JSON cannot hold one. The guard uses only `git` and POSIX `grep -E`, and it fails closed on its own errors. A missing `gitleaks` is the one exception: the guard skips the secret scan with a warning, so a new host can still commit.

On a host with no `agent-scripts` checkout, the hooks path does not exist and Git runs no hooks, with no warning. This is accepted. The backstop is a reusable `gitleaks` workflow in `agent-scripts`, called by each owned repo except forks of upstream projects. Claude Code denies `git commit --no-verify`, so an agent must stop and ask when the guard blocks it.

## Considered options

Per-repo opt-in `core.hooksPath` misses each new clone. The `pre-commit` framework needs a config file in every repo, and it has the same gap. Copying the hooks into `dotfiles` would reach every host, but it gives two copies that can drift.
