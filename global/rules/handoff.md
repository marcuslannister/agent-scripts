# Context handoff

A hook tells you when context fill reaches the handoff threshold. Then hand off the work to a new herdr tab:

1. Finish the current small step. Do not start a new step.
2. Write the handoff document with the `mattpocock-skills:handoff` skill. It is manual-only, so do not call the Skill tool: read its copy at `~/.agents/skills/handoff/SKILL.md` and follow it.
3. Create the tab and start the new agent in it:

   ```sh
   pane=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label <short-name> | jq -r .result.root_pane.pane_id)
   herdr agent start <name> --kind claude --pane "$pane"
   herdr agent prompt <name> "Read <handoff-file> and continue the work."
   ```

   If you are a coordinator (`herdr-coordinator` skill), use the label `"[coord] <work>"` and the name `coord-<work>`. Herdr agent names allow only lowercase letters, digits, `-`, and `_`.

   Do not put the prompt into `agent start`. It succeeds only when the agent is ready for input within its timeout. An agent that works on a start prompt is never ready, so `agent start` returns `timeout` and does not keep the name. If `agent start` does not return `agent_started`, run `herdr agent get <name>`. If the state is `blocked`, read the screen with `herdr pane read "$pane" --source visible` and show it to the user.

4. Tell the user which tab continues the work, then stop. Do not close your own tab.
