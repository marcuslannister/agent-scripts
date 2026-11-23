---
status: accepted
---

# Pi reads the inlined instruction artifact

This ADR supersedes one ADR-0010 clause: the Pi pointer. ADR-0010 said Pi follows the `agent-rules` links, so Pi points at the root `AGENTS.md`. Everything else in ADR-0010 remains in force, including the tracked artifact, the drift check, and ADR-0002's explicit-invocation rule for instruction pointers.

Pi 1.5.2 does not expand the `@` imports in `AGENTS.md`. A `pi -p` run from `/tmp` recorded its system prompt in the session file. The `project_context` section (2,445 B) holds the literal lines `@~/.claude/agent-rules/english.md` and `@~/.claude/agent-rules/tooling.md`. So the two rules that Claude Code always loads were not in the Pi prompt, and the model made no tool call to open them. The ADR-0010 check, a model asked to quote a rule behind one link, shows that a model can reach a linked rule. It does not show that Pi puts the always-loaded rules in the prompt. Whether Pi 0.84.2 expanded the imports was not checked.

Pi now points at `AGENTS.codex.md`, the artifact that Codex already reads: `AGENTS.md` with every `rules/` file inlined. Pi then has every rule in its prompt and follows no link. Setup replaces a Pi symlink that resolves to `AGENTS.md` in the same step that creates the new link, by the ADR-0010 rule for Codex: the resolved target proves setup wrote it. A later setup failure cannot leave Pi without a pointer. A regular file or a foreign symlink at the Pi path is preserved and reported, as before. The same step now also protects the Codex pointer.

The build and setup scripts that ADR-0010 names under `agent-tooling/` now live in `global/` of this repo (ADR-0013), with `AGENTS.md`, `rules/`, and `AGENTS.codex.md`: `global/bin/build-codex-instructions.sh` and `global/bin/setup-agent-instructions.sh`. The artifact keeps the name `AGENTS.codex.md`. A rename would change the tracked path that both pointers use, for no change in behavior.

## Considered options

Keeping Pi at the root `AGENTS.md` was the ADR-0010 decision. It leaves Pi without `english.md` and `tooling.md` unless the model chooses to open them, and the 1.5.2 session shows it did not.

## Consequences

A Pi request costs about 3.2k more input tokens. In the `pi -p "Reply OK."` run from `/tmp`, the provider-reported input went from 8,355 to 11,588 tokens, and `project_context` went from 2,445 B to 15,588 B. Pi also pays for the on-demand topic rules on every request, which is the cost the split avoids for Claude Code.

Codex and Pi now share one artifact, so one rebuild after an edit to `AGENTS.md` or `rules/` serves both, and `--check` guards both. A rule for only one of them needs a second artifact. A machine whose Pi pointer still resolves to `AGENTS.md` needs one explicit setup run to migrate it.
