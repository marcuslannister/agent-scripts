---
status: accepted
---

# Tracked Codex instruction artifact

`AGENTS.MD` split into a small root of hard rules plus topic files under `rules/`, linked from the root. Claude Code opens a linked file when a task needs it, which is the point of the split. Codex 0.149.1 has no import syntax: it concatenates the `AGENTS.md` files it finds and stops there, so a link is inert text and the split cost Codex nearly every rule it used to read.

Codex therefore reads a different artifact from Claude Code. `AGENTS.codex.md` is `AGENTS.MD` with every `rules/` file inlined, built by `agent-tooling/build-codex-instructions.sh`. It is tracked, not generated at install time. That is the whole decision: a pull refreshes it exactly like any other file, so the Codex pointer stays an ordinary symlink and no install lifecycle exists that could go stale. `--check` fails when the artifact drifts from its sources, and the test suite enforces that, so the artifact cannot be committed out of date. The build stages into a temporary file and swaps only after it succeeds; writing straight to the artifact would truncate it on a partial build, and a later `--check` would compare that same partial output against itself and report up to date.

Instruction pointers remain setup state under ADR-0002: `setup-agent-instructions.sh` runs only when the operator invokes it, and topology reconciliation never calls it. This ADR extends that clause rather than replacing it. Setup now recognizes one predecessor it wrote itself — the Codex pointer symlinked to `AGENTS.MD`, correct before the split and rule-destroying after it — and replaces it, because resolving the target proves the ownership. A regular file at that path is reported and left alone: the short-lived generated file carried no marker, so nothing distinguishes it from operator-authored rules, and guessing there is not worth the one manual deletion it saves. Foreign symlinks, including dangling ones, are preserved as before.

Topic links are written `~/.claude/rules/<name>.md`, and setup symlinks `~/.claude/rules` at the repo's `rules/`. A repo-relative link resolves against the agent's cwd, not against the file holding it, so it would break in every project except this checkout. Home-relative also keeps the tracked files free of machine-specific paths, which the global rules now forbid outright.

Unchanged: ADR-0001's one skills root per CLI, ADR-0002's explicit-invocation rule for instruction pointers, and ADR-0009's staging-only tooling. This ADR governs instruction files only and touches no skill distribution.

## Considered options

Generating `~/.codex/AGENTS.md` at install time was implemented first and reverted. It had no refresh trigger: no updater calls setup, and ADR-0002 forbids the routine path from doing so, so every later pull left Codex on stale rules while Claude Code was current. Calling setup from the updaters would fix the staleness by breaking ADR-0002, which is the wrong trade.

Keeping one file for both CLIs was the status quo and remains available at the cost of the split — either a flat root file, which is what progressive disclosure was meant to end, or a linked root that Codex cannot follow.

## Consequences

Editing `AGENTS.MD` or any `rules/` file is live for Claude Code immediately and requires `build-codex-instructions.sh` for Codex. That rebuild is the one step to remember; `--check` and the test suite catch a forgotten one before it lands. The tracked artifact duplicates its sources in the repository, so the two can disagree in a working tree, which is exactly what the drift check exists to detect. Machines that ran an earlier setup need one explicit run to migrate the Codex pointer; machines whose pointer is a regular file need the operator to delete it first, prompted by a warning that names the file and the fix.
