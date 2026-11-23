---
name: herdr-coordinator
description: "Make this session the coordinator (Method B), not an implementer. Analyze the work, split it into tasks by coupling and size, decide which tasks can run in parallel, and choose an agent for each task with the assignment rules (Claude Opus for UI design and frontend code, Sonnet for other code, verification, and research). Start each worker in a new Herdr tab, wait until it is really done, review the result with a review skill and a Codex Astra bug reviewer, pass information between agents, and report to the user. Use only when the user explicitly invokes herdr-coordinator."
disable-model-invocation: true
---

# Herdr coordinator

This session coordinates. It does not execute. The agents in their Herdr tabs write code, run code, debug, and test. You split the work into tasks, set the order, dispatch, track, review, and report.

The reason is context. Only your context holds the full picture of the work. It must last until the last task is reviewed, often hours later and after several compactions. If you edit files or debug errors yourself, the execution details fill your context, and nobody reviews the part that you did. Reads and writes are the same: each file that you read and each long text that you put in a command stays until the session ends, and each later request carries it. Thus, at each step, read only what you need for the decision, and write only what nobody else wrote.

You do these jobs yourself: read the plan to plan, read summaries to review, run the review in step 7, write the coordination record, update the files that you own, and commit your own files. Dispatch all edits to source or tests, all runs and debugging of the application, and each verification that needs a real run. A small change in the area of an agent goes to that agent.

Design background: `~/Projects/home/docs/research/herdr-multi-agent-roles.md` ("Method B"). This skill overrides two rules of the Herdr skill. You use Herdr because the user invoked this skill. In Claude Code the Herdr skill is manual-only (`skillOverrides`), so it does not load by itself; for CLI details beyond `--help`, read `~/.claude/skills/herdr/SKILL.md` or `~/.agents/skills/herdr/SKILL.md`. The first prompt to a worker names a task file and a result file.

## Before you start

1. Run `test "${HERDR_ENV:-}" = 1`. If it fails, say that the session is not in Herdr and stop.
2. Use the Herdr CLI to create tabs and to start and inspect agents (`herdr tab create`, `herdr agent start / list / get / read / prompt`). If you are not sure of an argument, read `herdr <command> --help` first. Do not guess. Do not run bare `herdr`, because it opens the TUI.
3. Read your own section in [Agents](#agents). Learn how your host tells you that a background command ended.
4. The monitor is `wait-settled.sh` in the folder of this skill (`~/.claude/skills/herdr-coordinator/` or `~/.agents/skills/herdr-coordinator/`).
5. Planning is your own job. The coordinator runs as Claude Code on Fable at high effort: `claude --model fable --effort high`. If Fable is not usable (for example "out of usage credits"), use Opus at the same effort: `claude --model opus --effort high`. If this session runs on another model, tell the user once, and continue.

## 1. Understand the work

Read the request and the plan that it points to, until you can split the work: the goal, the scope, the interfaces, the acceptance criteria, the dependencies, and the risks. Read code and long documents only to the module level (`eza`, `rg`, headings). Learn which modules, interfaces, and tests each part touches. Do not read all of it. Put what the workers must read in the "Required reading" of the record. Do not read it for them first, or the same material uses context in two places. For a previous phase or related coordination record, read only the decision table and the status. For old summaries, read only the coordinator summary.

Small lookups (paths, symbols, call sites, tests) go to the `Explore` subagent, not to a Herdr tab. A tab starts a full interactive agent, which is too heavy for a lookup. Ask Explore for paths and evidence, not full files.

Look at the current state: does `herdr agent list` show other agents in the same checkout, and does `git status` show changes that are not yours? Ask the questions that change the split now. If the plan is not detailed enough, and a split needs a large read of code, make an exploration the first read-only task. Its result must fit on one screen: module boundaries, interfaces, risks, and a proposed split. Do not do the read yourself.

## 2. Split and order

Split by "which changes change together", not by the words of the request.

- A task is one complete change that one agent can finish in one session and prove itself, with done criteria that another person can check.
- Keep the same files, the two sides of one interface, and the same set of tests in one task. If you split them, two agents guess at each other's half-done work.

Order:

- If B needs the code, the interface, or the conclusion of A, dispatch B only after you accept A. Write the B task from the real result of A. Code written against a guessed interface must be done again.
- Read-only tasks (research, review) can run in parallel with any task.

If the work comes from a plan that the user approved, write the record and start, and show the split when you start. If the split contains a choice that the user will want to make, ask first.

## 3. Choose the agent

Set the agent kind of each task when you split it, and write it in the task table. Dispatch, rework, and handover all use the table. Do not choose again at dispatch. After a compaction or a new session, the record is the only place where the kind is.

Use the first rule that applies:

1. The user gave a kind, model, or effort for this task: use it.
2. The user gave one for all the work (for example "all Opus" or "all Codex this time"): use it.
3. Otherwise, use the default assignment. Take the first match from the top:
   - **Verification goes to Sonnet**: `--kind claude`, with `--model sonnet --effort xhigh` in the start arguments. Verification is work that needs a real run: run the application, take screenshots, E2E, tests on a device.
   - **Research goes to Sonnet**: `--kind claude`, with `--model sonnet --effort xhigh` in the start arguments. Research is a task that opens web pages, fetches documents, or reads many sources.
   - **UI design and frontend code go to Claude Opus**: `--kind claude`, with `--model opus --effort xhigh` in the start arguments.
   - **All other work goes to Sonnet**: `--kind claude`, with `--model sonnet --effort xhigh` in the start arguments. This includes the backend, scripts, and CI.

Pass the model and the effort explicitly for each kind, so that a worker does not depend on the settings of the machine.

Code review is not a task in this table. Step 7 sets it: Codex Astra at medium effort. All code comes from Claude workers, so the review comes from a second vendor. Check the valid Codex model names with `codex debug models`.

The kind of the coordinator (Claude Code or Codex) does not change the kind of the workers.

What is frontend:

- Yes: UI design and all code in the frontend. This includes pages and components, styles, interaction and animation, UI text, the design system and tokens, and also frontend state, the data layer, the API client, routing, build configuration, and tests. A UI review (judge the design from screenshots) is also frontend. The UI layer of a native app is also frontend.
- No: the backend and server API, databases, scripts, CI and deployment, and the parts of a native app outside the UI layer.

An exploration task that reads code for the split (step 1) is not research. Classify it by what it explores: frontend or other.

If the work changes the frontend and the backend, split it at the interface. Sonnet does the backend and the interface first. After you accept it, Opus does the frontend from the real interface (step 2: dispatch B after you accept A). If the change is too small to split, give all of it to the side where most of the change is.

If a worker may open its own helper tabs, use this step to set their kind in the shared constraints. If the selected kind is not in `herdr agent start --help`, or its usage limit is reached, ask the user. Do not change to another kind yourself.

## 4. Coordination record

Before the first dispatch, make the coordination record in a folder of the project that Git ignores, for example `tmp/<date>-<work>/`, with the start date. If the project does not ignore it, add the folder to `.git/info/exclude`, not to `.gitignore`. Write in the user's language, and give the reason for each rule. All records, including rework tasks, go here and are not committed: they record the coordination only, and in Git each status update makes one more commit. Scripts, generated files, and evidence from research and verification also go here, from you and from the workers. Screenshots go in `screenshots/`. Use only this one folder for all the work, and write its path in each task file. If a worker chooses a place, it makes a second folder, and the user must look in two places.

The record has four kinds of files. Keep the stable content apart from the content that changes, and write only the change each time. In each file, the part that grows (a table or log that gets new lines) is the last section. Then a new line that is appended to the file lands in the correct section.

- **`brief.md`**: shared by all workers. It seldom changes after you write it. At the top, say that the coordinator wrote this file, and that a worker can object to a coordinator decision in its summary. Keep the sections in this order:
  - **Required reading**: what all workers read first, and what each task reads, to the file and section.
  - **Task table**: task, agent name, agent kind, dependencies, how to verify, task file.
  - **Shared constraints**, at minimum:
    - Do only your own task. Do not start the next one. Do not edit the coordination record.
    - Work on the task branch that the task file names. Commit there, so the review has a base revision.
    - `git add` only your own files. Do not stash, check out, or reset uncommitted changes of other people.
    - Whether the worker can open helper tabs (if yes, which kind, and the worker stays responsible for them).
    - Which shared files the coordinator owns (for example the issue list, the to-do list, the root `AGENTS.md`, the progress checkboxes of the plan). Findings outside the scope go to "For the coordinator" in the summary.
    - If a permission or trust dialog opens, stop and wait. Do not answer it with a guess.
  - **Deliverable**: a summary at a fixed path. Its first section is `## Coordinator summary (<agent name>)`, 15 lines at most: the result, the commits, where the evidence is (test output and counts, screenshots, measurements), the worker's own decisions, what is not verified, and what is for the coordinator. The code and the summary go in the same commit. Do not commit only for progress or for the summary. A task without code changes (research, verification) does not commit. The last reply in the tab gives the commit hash (if there is one) and the summary path.
  - **Decision table**, the last section: number, question, decision, who decided. Add each new decision as a new row at the end of the file.
- **`tasks/<agent name>.md`**: one for each dispatch. Rework, handover, and experiments each get a new one. It contains: the base revision and the task branch, the scope, what not to do, the done criteria, the checks to run, and what to read this time. Write a new file. Do not append to `brief.md`.
- **`status.md`**: only you edit it. For each task: the state (planned, in progress, to review, rework, waiting for the user, accepted), the agent name and tab, the result commit, and the wait handle when necessary. Also the review baseline (the last commit that you reviewed). The last section is the log, with one line for each event: append each new line at the end of the file. To change a state, replace only that line. Do not put the full old and new text in a command with a script.
- **`handover.md`**: only when you hand over (step 8). It is a separate file, so the log stays the last section of `status.md`.

In a task file, write only what nobody else wrote. For background, findings, and review comments, give the path and section (for example "Fix items 1 and 3 in review.md. Do not change item 2, see decision 17"). Do not repeat the text: you write it once and the worker reads it once, and both use context for nothing. For a handover, first tell the old agent to write a "Handover" section in its own summary (how far it got, the next step, the problems it found). The new task file points to it and adds only your decisions. Write the handover yourself only if the old agent is gone.

If a task starts a service for the user to look at (a preview page, a local site) and keeps it until the user confirms, then starting, keeping, and stopping the service are all in the scope of that task. Do not give them to another task: the next agent can only manage a process that it did not start. Write this in the task file:

- Run it as a managed process. Claude Code uses `run_in_background` of Bash. Codex and other agents without background jobs open a second Herdr pane in their own tab and run it in the foreground. After delivery, the agent stays in its tab and keeps the service.
- Do not use `nohup`, `setsid`, `disown`, or `start_new_session=True`. Such a process leaves management, the user cannot see it, and the only way to stop it is to kill a pid.
- Put the URL, the background job or pane, and how to stop it in the summary and in the last reply.

These files are your memory outside the context. Compaction, a resumed session, a usage limit, and a new session all lose what is only in your head, and an old memory makes you dispatch again or report an old state. Thus, update `status.md` first, then act.

One commit delivers the change of one development task. Do not commit only for progress. Keep the shared files that you own in the working tree, not added, with the summaries that the workers leave there, and commit them all once at the end. For long work, you can commit them after you accept a group of related tasks.

If a worker finds a trap for later workers (a hook that reorders a whole file, a command that loses uncommitted changes), add it to the shared constraints before the next dispatch. If the record has a change that you did not make: a change from the user is a new rule, and a change from a worker is out of scope.

## 5. Dispatch

For each task that can start:

1. Make sure that it is not running: check `status.md` and `herdr agent list`.
2. Make the task branch and record the base revision in the task file.
3. Open a new tab in the current workspace and folder, without focus, with the agent name as the label:
   `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label <agent name> --no-focus`
   The root pane id is `.result.root_pane.pane_id` in the JSON. Start the agent in that pane:
   `herdr agent start <agent name> --kind <kind> --pane <root pane id> -- <start arguments>`
   The shell of a new tab can need some seconds. If you get `agent_pane_busy`, wait and try again.
4. Codex and Claude Code show a "Trust this folder?" dialog on their first start in a folder. `agent start` can return `agent_not_ready` ("blocked during startup"), or it can return `agent_started` before the dialog shows. Thus, after `agent start`, run `herdr agent get <agent name>`. If the state is `blocked`, read the screen with `herdr pane read <pane id> --source visible`; the default source can show an old screen. Show the dialog to the user and ask before you answer it. Do not answer it yourself.
5. Use the kind, the model, and the start arguments from the task table ([step 3](#3-choose-the-agent)).
6. Give the task with `herdr agent prompt <agent name> "<prompt>"`. The prompt has only some sentences: which task, which sections of `brief.md` and `tasks/<agent name>.md` to read, continue until the done criteria are met without a wait for confirmation, and reply as the deliverable says at the end. Add the changes since you wrote the record (for example "Task D is done in <commit>, and all tests pass again"). Do not add `--wait`.
7. After `agent start` succeeds, start the monitor and update `status.md`.

Name each agent `<work>-<task>` (for example `refactor-p3-http`), so that `herdr agent list` keeps it apart from the agents of other projects.

## 6. Wait

Do not wait for results with `herdr agent wait` or `agent prompt --wait`. They return at the first pause, and in a long task the agent is often idle for a short time between steps. Give each running agent one monitor, and run it in the background:

```bash
bash ~/.claude/skills/herdr-coordinator/wait-settled.sh <agent name> 480
```

Run the command as it is shown, with nothing after it (no `; echo`). Then the exit code of the monitor is the exit code of the background command, and the completion notice shows it without one more read.

The monitor checks `herdr agent get` each 45 seconds. It ends when three checks in a row are `idle` or `done` (exit 0). It ends at once on `blocked` (exit 2), because the agent waits for a person. It also ends when the agent is gone (exit 3) or after the timeout in minutes (exit 4). A timeout is not a failure of the task: read the agent state before you send anything again. Do not send the prompt again.

- **Get the result the way your host does it.** One host wakes you when a background command ends. Another host gives only a handle that you must poll. See [Agents](#agents). If you do this wrong, the coordination stops and nothing tells you.
- **One monitor for each agent.** Before you start one, and specially after a wait was interrupted or cut, or after a session resumed, run `pgrep -fl "wait-settled.sh <agent name>"`. If the old one runs and you can get its result, keep it. If it runs and you cannot get its result, kill it and start a new one. Two monitors send two signals for one event, and if you act on both, you dispatch the work two times.
- **Blocked.** Read the screen with `herdr agent read <name> --source recent-unwrapped --lines 30`. If that is empty (Codex dialogs can be), use `herdr pane read <pane id> --lines 30`. Show the dialog to the user and ask before you answer. For Claude Code and Codex, Herdr reads the state from the screen. A new kind of dialog can show as `idle`. If a summary is missing after `idle`, read the screen before you type into the tab.

## 7. Review

When the monitor returns `done` or `idle`, read the coordinator summary first. Do not read the terminal or the full summary:

```bash
awk '/^## Coordinator summary \(<agent name>\)/{f=1; print; next} f && /^## /{exit} f' <summary path>
```

Read the terminal only when the monitor reports blocked, timeout, or agent gone, or when there is no summary, and limit the lines (`herdr agent read <name> --source recent-unwrapped --lines 30`). In the full summary, read only the section that you need: when the summary and the evidence do not agree, or when you need the details of an unverified item or of an item for the coordinator. For details that the next task needs, give that task the path and section, and let it read them.

A task with code changes gets a review in two parts. Both use the base revision from the task file. Give each reviewer the verified facts about the environment (probe output, API shapes, tool versions), not only the diff, so it does not report guesses as findings. This is the same rule as step 5 of `/architect`. Keep the two skills the same.

- **Second review, chosen by size**: if the diff has fewer than about 200 changed lines in one module, run the `ponytail:ponytail-review` skill on it. Otherwise, run the `mattpocock-skills:code-review` skill. Use the base revision as the fixed point and the task file as the spec.
- **Bugs, regressions, and security, on every diff**: dispatch the review to Codex in a new tab as a read-only task (step 5): `--kind codex`, with `-m gpt-6.2-astra -c model_reasoning_effort=medium` in the start arguments. First write the diff to the record with `git diff <base>...HEAD -- . > <record>/evidence/<agent name>.diff`, from the repository root, and give the reviewer that path. Its report goes to a fixed path and starts with a summary: the conclusion, then one line for each finding (number, severity, location). If the Codex usage limit is reached, give the diff file to the `reviewer` subagent instead, and write this in the decision table. The subagent cannot run `git`, because a hook blocks Git reads, so it needs the file.

Accept or reject each finding with evidence.

Check:

- The done criteria are met, with evidence: test output and counts, screenshots, measurements, not only "tests pass".
- The worker stayed in scope. Record its own decisions and report them to the user.
- You handled each item in "For the coordinator": text for the shared files, objections to your decisions, and problems that it found.
- When the worker closes an issue or gives a root cause, the claim and the evidence agree. If not, ask.

If the task left a service for the user, after the check give the user the URL and how to look at it. Set the state to "waiting for the user", and do not accept yet. After the user confirms, tell the original agent with `agent prompt` to stop the service and report. Then accept. Do not kill the pid yourself: this session does not execute, and only the original agent knows the background job or pane of the service.

Do only light checks yourself (the summary, the review, the diff stat, the commit). If a check needs a run of the tests or the application, send it back to the agent or dispatch a verification task. Send rework to the original agent first, because it knows the code. Use `agent prompt` with the path of the review findings. After the rework, review the changed part again. If the context of the original agent is almost full, start a new agent, and first get the handover as in step 4.

After you accept: set the state to accepted, move the review baseline to the commit that you reviewed, update the files that you own, and tell the agents that depend on this change what changed and what to read again. Then check your own context as in [step 8](#8-recover-and-hand-over).

## 8. Recover and hand over

After a compaction, after a resumed session, after you take over, or when you are not sure of the state, rebuild the state from the sources before you dispatch or report:

1. Read `status.md`, and `handover.md` if it exists.
2. Run `herdr agent list`. For each task that is not accepted, run `herdr agent get <name>`: does it exist, and what is its state?
3. Run `pgrep -fl wait-settled.sh`, and compare the monitors with the record.
4. Run `git log --oneline <review baseline>..HEAD` and `git status --short`: what landed while you were away?
5. Correct the record, start only the missing monitors, and continue.

If the record shows a task as running, do not dispatch it again until you know that its agent is gone. When the user asks for progress, report what you just checked, not what you remember.

Context only grows. A record on disk does not remove old history from it. Thus, long work needs a new session. After each acceptance, check how much of your context is in use (in the way that your environment shows it; if you cannot see it, skip this). If it is more than 35%, hand over at this acceptance point. Do not wait until it is higher:

1. Update `status.md`. Write `handover.md`, 20 lines at most: what you wait for, the next step, and the judgments and spoken user decisions that are not yet in the record.
2. Kill the monitors that this session started (`pkill -f "wait-settled.sh <agent name>"`). If they stay, they wake this session when they end, and two coordinators act.
3. Open a new tab in the current workspace, and start an agent of your own kind. A Claude Code coordinator always starts the new one on Opus: `--model opus --effort high`. This avoids a Fable failure in the middle of the work. Name it `<work>-coord<N>`. The prompt invokes this skill explicitly (`/herdr-coordinator` in Claude Code, `$herdr-coordinator` in Codex), followed by: "Take over the coordination in tmp/<date>-<work>/: recover as in step 8, then continue."
4. Tell the user which tab took over. This session then stops: it does not dispatch, and it does not reply to agents.

If the user wants a `/compact` in place, do it. After the compaction, also start with the recovery steps above.

## 9. Finish

- Tick the plan as the project rules say. Update the issue list and the to-do list of the project.
- Report each task: what it did (commits, summary), what the agent decided, what is not verified or is postponed, and what the user must decide.
- List the tabs that you opened, and ask the user whether to close them (the user can want to read the records first). Make sure that each agent stopped the services, simulators, and browser sessions that it started.
- Commit the files that you own and the summaries that the workers left in the working tree, in one commit, as the repository rules allow. Coordinator mode does not authorize commits, pushes, or releases. The record stays in `tmp/<date>-<work>/`.

## Kanzo

Use this section when the user names a Kanzo task (like `home#12`) or asks you to track the work in Kanzo. Kanzo is the only issue board. Do not use `tsk`.

Kanzo holds what to do: the issue, its state, and short progress notes for the user. The coordination record holds how this run does it. `status.md` stays the source of truth, and Kanzo only mirrors it.

- **Only you write to Kanzo.** Workers do not, and their task files do not mention it. One writer keeps the board correct and keeps the context of the workers small.
- **At the start:** read the task with `get_task`, including its comments, as the input for step 1. Set `status: doing`. Write the task ID at the top of `status.md`.
- **After each acceptance:** add one comment with `add_comment`: the task, the commit, and the summary path. Keep it to one or two lines. Do not copy the summary.
- **Findings outside the scope:** for each item in "For the coordinator" that does not belong to this issue, create a follow-up task with `create_task` in the same project. Give it a short description and the path of the evidence. Tell the user the new IDs.
- **When you finish or are stuck:** set `status: review` with `update_task`, and add a comment: what is done, what is open, and how to resume (the record folder and the coordinator tab). If you opened a pull request, set `url`.
- **Handover (step 8):** the prompt to the new coordinator names the task ID. The new coordinator writes to the same task.
- **Do not** set `done`, and do not change a task with `human: true`. The user does those.
- Kanzo runs over HTTP and cannot see your folder. Pass `project` when you create a task. `list_projects` gives the slugs.

## Agents

### Claude Code

A background command wakes you when it ends. Start the monitor with `run_in_background` of Bash, and come back on its completion notice. While a monitor runs, you can end your turn. Say in one or two sentences what runs and what you wait for.

### Codex

A background command does not wake you when it ends. When the tool call returns, the command still runs, and you get only a session id. To get later output, poll with that id (`write_stdin` with empty input).

- Write the session id of each monitor in `status.md`. After a compaction, it is the only place to find it.
- During coordination, do not end your turn. Poll in the turn. When more than one agent runs, poll their sessions in turn.
- After a wait is interrupted (the user pushes Esc, or a poll is cut), the monitor process usually still runs. Find it with `pgrep`, and continue to poll with the session id from the record. Do not start a second one.
- When you need a decision from the user, ask, and continue to poll the other agents. The reply of the user arrives during the turn.
