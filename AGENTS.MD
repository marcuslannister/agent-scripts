Global agent rules. `agent-tooling/setup-agent-instructions.sh` points the Claude Code and Codex instruction paths at this file.

Hard rules only. Topic detail lives in the linked files. Skills own tool workflows.

## Topic rules

Open the file that matches the task before you start it. Codex reads these inlined below instead, because it has no import syntax.

- [Git](~/.claude/rules/git.md) — where to work, branches, commits, shared trees.
- [GitHub, CI, and shipping](~/.claude/rules/github.md) — `gh` mechanics, pull requests, issues, `fix ci`, `ship`, releases, changelog.
- [Tools and task routing](~/.claude/rules/tooling.md) — find code, Anvil edit tools, `$codex-first`, background tasks, shell footguns.

## Communication

Applies to every reply.

- Talk in ASD-STE100 Simplified Technical English. Read `CONTEXT.md` files and use their ubiquitous language.
- Check the user's message against `~/.claude/rules/english.md` and correct real mistakes per its patterns.
- Use bullets only for genuinely enumerable items, checklists, or side-by-side choices. Do not turn every sentence, observation, or implementation detail into its own bullet.

<important if="the user says 'make a note' or asks you to record a rule">
Make a terse edit to the rules file that matches the topic. Do not create a separate `CLAUDE.md`.
</important>

<important if="you are about to commit, push, tag, publish, release, or run reset/clean/restore/force-push/rebase/filter-repo">

- Never ship automatically. Push only when the user asks for it in the current task, or when the user invoked a workflow that says it pushes. No repository is exempt, including `manager`, `conferences`, and `agent-scripts`. A repo-local rule can define push mechanics, but it cannot grant push authority.
- Finishing a task is not authorization to commit, push, tag, or publish. Leave the work in the tree and say it is ready.
- Never rewrite published history — `push --force`, `rebase` onto a pushed base, `filter-branch`, `filter-repo` — without an explicit request for that specific rewrite.
- `reset --hard`, `clean`, and `restore` need an explicit user request every time.
- Task-scoped file deletion is allowed. Never delete or overwrite unknown or unrelated user data.
</important>

<important if="the task touches a secret, a token, an API key, or environment variables">

- Never reveal a secret value, not even an internal one. Use the approved secret tools and redact the output.
- Never run `env`, `set`, `export -p`, or a broad secret regex dump in a normal shell. Query the exact name only.
- After you handle a secret or an environment variable, unset the token environment before a public `gh` write: `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN ...`.
</important>

<important if="you are sending anything outward — a GitHub comment or body, an email, an upload, or any external service call">

- If the audience or the destination is unclear, ask first. Confidentiality alone does not block internal research or internal answers.
- Never inline double-quoted text in a public GitHub body when it contains backticks, `$`, a shell snippet, an environment name, or user text. Write a temp file with `cat <<'EOF'`, inspect it, then pass `--body-file`.
</important>

<important if="you are writing or editing any file, commit message, or generated artifact">

- No personal identifiers. No local account name, no home directory name, no real name, no email address. `~` is the only correct way to say "the user's home directory".
- No absolute or machine-specific paths. Derive a path from the repository root, from `$HOME`, or from the script's own location. A path that only resolves on one machine is a defect, including in docs, comments, tests, and generated files.
</important>

<important if="you are fixing or refactoring and consider keeping an old path, alias, shim, or fallback">
Delete the old path by default. Compatibility needs a named contract: a public API, CLI, config, or data format; a tagged upgrade; a security boundary; or observed production state. Tests alone are not a contract. If you are unsure, ask.
</important>

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
