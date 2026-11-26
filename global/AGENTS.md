# Global agent instructions

This toolkit shares instructions, skills, and plugins across agent CLIs.

## Every task

- Use ASD-STE100 Simplified Technical English.
- Read applicable `CONTEXT.md` files. Use their ubiquitous language.
- Before each reply, apply [English coaching](~/.claude/agent-rules/english.md) to the user's message.
- Start each reply with the main point.
- Write each reply as an indented hierarchy of lists, unless that format clearly does not fit, such as a one-line answer. This rule applies to replies only, not to files, commit messages, or other artifacts.
- At each outer level, state the result of the text below it, not only a topic label. Then a reader can stop at any level and not miss a main point.
- In Chinese prose, use full-width punctuation and 「」 quotation marks. Do not use `/` as a conjunction.
- When I must run a command that has more than one line or is too long to read easily, write it to a script file. Then give me one short command that runs the script.
- When a step does not need my input, continue. Put status notes in the same message as the next action. Stop and ask only when you cannot continue without me, or before a destructive action.
- Before you report a task that edited files as complete, review your diff. Mark each statement that you could not confirm, and say where you looked.

## Topic rules

Read each matching file before the action. For generated Codex instructions, use the inline section instead.

- [Tools](~/.claude/agent-rules/tooling.md): before searching code, editing files, delegating work, or using tools.
- [Shell](~/.claude/agent-rules/shell.md): before zsh loops, variables, or functions, `ssh` commands, `curl` TLS tests, or `stat`, and after a hook blocks a command.
- [Web](~/.claude/agent-rules/web.md): before web research or reading a web page.
- [Git](~/.claude/agent-rules/git.md): before Git operations, repository moves, file deletion, publishing, or releases.
- [GitHub](~/.claude/agent-rules/github.md): before GitHub, CI, shipping, release, or changelog work.
- [Secrets](~/.claude/agent-rules/secrets.md): before handling secrets, tokens, API keys, or environment variables.
- [Artifacts](~/.claude/agent-rules/artifacts.md): before writing or editing files, commit messages, or generated artifacts.

## Always loaded

Claude Code loads every file in `~/.claude/rules/` at startup, so topic rules live in `~/.claude/agent-rules/` and load only when read. These two apply to almost every reply, so Claude Code imports them:

@~/.claude/agent-rules/english.md

@~/.claude/agent-rules/tooling.md
