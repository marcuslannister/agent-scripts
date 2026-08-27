Global agent rules. `agent-tooling/setup-agent-instructions.sh` points the Claude Code and Codex instruction paths at this file.

Hard rules only. Everything below applies to every task. Topic detail lives in the linked files — open the one that matches the task before you start it. Skills own tool workflows.

## Communication

- Use bullets only for genuinely enumerable items, checklists, or side-by-side choices. Do not turn every sentence, observation, or implementation detail into its own bullet.
- Always talk in ASD-STE100 Simplified Technical English. Always read `CONTEXT.md` files and use their ubiquitous language.
- "Make a note" means a terse edit to the rules file that matches the topic. Do not create a separate `CLAUDE.md`.
- Before every reply, check the user's message against `~/.claude/rules/english.md` and correct real mistakes per its patterns. This runs every turn, not only when a task routes to it.

## Secrets

- Never reveal a secret value, not even an internal one. Use the approved secret tools and redact the output.
- Never run `env`, `set`, `export -p`, or a broad secret regex dump in a normal shell. Query the exact name only.
- After you handle a secret or an environment variable, unset the token environment before a public `gh` write: `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN ...`.

## Push and destructive operations

- Never ship automatically. Push only when the user asks for it in the current task, or when the user invoked a workflow that says it pushes. No repository is exempt, including `manager`, `conferences`, and `agent-scripts`. A repo-local rule can define push mechanics, but it cannot grant push authority.
- Finishing a task is not authorization to commit, push, tag, or publish. Leave the work in the tree and say it is ready.
- Never rewrite published history — `push --force`, `rebase` onto a pushed base, `filter-branch`, `filter-repo` — without an explicit request for that specific rewrite.
- These Git operations need an explicit user request every time: `reset --hard`, `clean`, `restore`.
- Task-scoped file deletion is allowed. Never delete or overwrite unknown or unrelated user data.

## Sending things outward

- If the audience or the destination is unclear, ask before you send anything external. Confidentiality alone does not block internal research or internal answers.
- Never inline double-quoted text in a public GitHub body when it contains backticks, `$`, a shell snippet, an environment name, or user text. Write a temp file with `cat <<'EOF'`, inspect it, then pass `--body-file`.

## Never write these into a file

- No personal identifiers. No local account name, no home directory name, no real name, no email address. `~` is the only correct way to say "the user's home directory".
- No absolute or machine-specific paths. Derive a path from the repository root, from `$HOME`, or from the script's own location. A path that only resolves on one machine is a defect, including in docs, comments, tests, and generated files.
- These apply to committed files, generated artifacts, commit messages, and anything sent to a remote.

## Compatibility

- On a fix or a refactor, delete the old path by default. Compatibility needs a named contract: a public API, CLI, config, or data format; a tagged upgrade; a security boundary; or observed production state. Tests alone are not a contract. If you are unsure, ask before you add an alias, a shim, or a fallback.

## Topic rules

Open the file that matches the task before you start it. Codex reads these inlined below instead, because it has no import syntax.

- [Git](~/.claude/rules/git.md) — where to work, branches, commits, shared trees.
- [GitHub, CI, and shipping](~/.claude/rules/github.md) — `gh` mechanics, pull requests, issues, `fix ci`, `ship`, releases, changelog.
- [Tools and task routing](~/.claude/rules/tooling.md) — find code, Anvil edit tools, `$codex-first`, background tasks, shell footguns.

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
<!-- >>> claude-env chrome >>> -->
# Claude for Chrome

- Use `read_page` to get element refs from the accessibility tree
- Use `find` to locate elements by description
- Click/interact using `ref`, not coordinates
- NEVER take screenshots unless explicitly requested by the user
<!-- <<< claude-env chrome <<< -->
