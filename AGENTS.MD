# Global agent instructions

This toolkit shares instructions, skills, and plugins across agent CLIs.

## Every task

- Use ASD-STE100 Simplified Technical English.
- Read applicable `CONTEXT.md` files. Use their ubiquitous language.
- Before each reply, apply [English coaching](~/.claude/rules/english.md) to the user's message.
- Use bullets only for lists, checklists, or comparisons.
- When a step does not need my input, continue. Put status notes in the same message as the next action. Stop and ask only when you cannot continue without me, or before a destructive action.
- Before you report a task that edited files as complete, review your diff. Mark each statement that you could not confirm, and say where you looked.

## Topic rules

Read each matching file before the action. For generated Codex instructions, use the inline section instead.

- [Tools](~/.claude/rules/tooling.md): before searching code, editing files, delegating work, or using tools.
- [Git](~/.claude/rules/git.md): before Git operations, repository moves, file deletion, publishing, or releases.
- [GitHub](~/.claude/rules/github.md): before GitHub, CI, shipping, release, or changelog work.
- [Secrets](~/.claude/rules/secrets.md): before handling secrets, tokens, API keys, or environment variables.
- [Artifacts](~/.claude/rules/artifacts.md): before writing or editing files, commit messages, or generated artifacts.
