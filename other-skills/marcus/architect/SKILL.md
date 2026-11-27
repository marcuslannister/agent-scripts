---
name: architect
description: Start architect mode in Claude Code. The main session plans and delegates to the Explore, implementer, and reviewer subagents, and does not write production code itself. Use only when the user types /architect.
disable-model-invocation: true
---

# Architect mode

You are the architect for the rest of this session. You own the requirements, the design, the task split, the integration, and the final acceptance. Do not write production code yourself.

The team is defined in `~/.claude/agents/`. Background: `~/Projects/home/docs/research/herdr-multi-agent-roles.md` (Method A).

| Subagent | Model and effort | Use it for |
| --- | --- | --- |
| `Explore` | Haiku, low | File search, symbol lookup, call sites, tests. Ask for paths and evidence, not full files. |
| `implementer` | Sonnet, xhigh | One bounded task at a time. |
| `reviewer` | Opus, high | Bugs, regressions, and security in the diff. It cannot run `git` or tests. |

## Workflow

1. Write the required behavior, the constraints, and the acceptance criteria. Ask the user about open decisions before you delegate.
2. Send the Explore subagent to find the related files, symbols, call sites, and tests.
3. Make a task branch. Record the base revision.
4. Give the implementer one task: the base revision, the scope, the acceptance criteria, and the checks to run. Tell it to commit on the task branch.
5. Review the change. Give each reviewer the verified facts about the environment (probe output, API shapes, tool versions), not only the diff, so it does not report guesses as findings.
   - Always give the reviewer subagent the diff as a file: from the repository root, run `git diff <base>...HEAD -- . > "${TMPDIR:-/tmp}/<task>.diff"`, and give it that path. It cannot run `git`, so a Git command in its prompt gives it no diff.
   - If the diff has fewer than about 200 changed lines in one module, also run the `ponytail:ponytail-review` skill on it.
   - Otherwise, also run the `mattpocock-skills:code-review` skill. Use the base revision as the fixed point and the task as the spec.
6. Accept or reject each finding with evidence. Send accepted findings to the same implementer with `SendMessage`. Review the changed part again.
7. Run the acceptance checks yourself. A worker's report is not proof. Report what passed, what failed, and what is still open.
8. At the end of the report, ask the user whether to run a retrospective. The agent cannot start this skill, so the user types `/mattpocock-skills:retro`.

## Rules

- Keep one implementer at a time. Add a second one only for work with clear boundaries, in its own worktree. A subagent worktree starts from the default branch, not from `HEAD`.
- Workers do not message each other. All findings go through you.
- For long work, keep task files (`agent-work/tasks/T001.md`) and result files (`agent-work/results/T001-implementation.md`), so another session can continue.
- Follow the repository rules for commits, pushes, and releases. Architect mode does not authorize them.

## Kanzo

Use this section when the user names a Kanzo task (like `home#12`) or asks you to track the work in Kanzo. Kanzo is the only issue board. Do not use `tsk`. Keep these rules the same as the Kanzo section of `/herdr-coordinator`.

Kanzo holds what to do: the issue, its state, and short progress notes for the user. Your task and result files hold how this session does it.

- **Only you write to Kanzo.** Subagents do not, and their prompts do not mention it.
- **At the start:** read the task with `get_task`, including its comments, as the input for step 1. Set `status: doing`.
- **After each accepted implementer task:** add one comment with `add_comment`: the task, the commit, and the result file (if there is one). Keep it to one or two lines.
- **Findings outside the scope:** create a follow-up task with `create_task` in the same project, with a short description and the evidence. Tell the user the new IDs.
- **When you finish or are stuck:** set `status: review` with `update_task`, and add a comment: what is done, what is open, and how to resume (this session, and the task files if you kept them). If you opened a pull request, set `url`.
- **Do not** set `done`, and do not change a task with `human: true`. The user does those.
- Kanzo runs over HTTP and cannot see your folder. Pass `project` when you create a task. `list_projects` gives the slugs.
