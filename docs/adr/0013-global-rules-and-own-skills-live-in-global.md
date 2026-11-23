---
status: accepted
---

# The global rules and own skills live in `global/`

The global rules, the generated Codex file, the pointer setup scripts and their tests, and the own skills now live in `global/` of this repo. This reverses the 2026-11-15 move of these files to the private `home` repo.

Reason: a Windows PC must not clone the private `home` repo. This repo is public and is already on every PC, so a PC that has this repo has the rules and the own skills.

Layout in `global/`, the same as `home` had: `AGENTS.md`, `AGENTS.codex.md`, `rules/`, `skills/` (`anvil-advanced-ops`, `architect`, `herdr-coordinator`), `bin/`, and `tests/`. One folder, not the repo root, because the upstream root has `AGENTS.MD` (ADR-0008 excludes it), and a root `AGENTS.md` would clash with it on a file system that ignores case. A folder also keeps the root an upstream mirror plus local tooling.

## Decisions

- The files are a plain copy in a new commit, with no Git history. The old history stays in the private `home` repo, so no old private line becomes public.
- `refresh-mac` stays in `home`. It is a Mac-only project skill and names no moved path.
- `global/skills/` is not the root `skills/`, the upstream mirror. The matrix, `validate-skills`, and the generators do not read it. `global/bin/install-skills.sh` copies each skill as a plain directory, without a marker, so the matrix sync keeps it.
- `global/AGENTS.codex.md` has every rule except `rules/handoff.md`: only the Claude Code context-handoff hook reads that file, and Codex and Pi have no such hook.
- Every script finds its root with `..` from its own folder, so none needed a path change.
- `agent-tooling/verify.sh` runs `global/tests/*-test.sh` in the section "Global rules and own skills", so CI runs them too. The `.ps1` test is not run there.
- The four pointers on the Mac are relative links into `global/`. The Bash setup makes relative links where `realpath --relative-to` works, and the PowerShell setup makes absolute links. ADR-0010, ADR-0012, and ADR-0002 keep their rules for setup, ownership, and the tracked artifact.

## Consequences

The four pointers are links that Git tracks: `CLAUDE.md` and `agent-rules` in claude-code-settings, `AGENTS.md` in codex-settings, and `agent/AGENTS.md` in pi-settings. A machine whose `~/.claude`, `~/.codex`, and `~/.pi` are these repos gets the new links when it pulls them. Pull in this order:

1. Pull `agent-scripts`, so the new targets exist.
2. Pull the three settings repos.
3. Check that the four pointers resolve into `global/` and that `~/.claude/agent-rules/tooling.md` is readable.
4. Pull `home` last, because it deletes the old targets.

Only a pointer that is not the tracked link needs a manual step, for example a link made by hand. Setup keeps a foreign symlink, and a link to `home` is foreign to it. Remove that pointer, then run `global/bin/setup-agent-instructions.sh`.

The skills in `global/skills/` still link to `~/Projects/home/docs/research/`. These links work on the Mac and are background reading elsewhere.
