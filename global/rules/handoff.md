# Context handoff

A hook tells you when context fill reaches the handoff threshold. Then hand off the work to a new herdr tab:

1. Finish the current small step. Do not start a new step.
2. Write the handoff document with the `mattpocock-skills:handoff` skill. It is manual-only, so do not call the Skill tool: read its copy at `~/.agents/skills/handoff/SKILL.md` and follow it.
3. Create the tab and start the new agent in it:

   ```sh
   pane=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label <short-name> | jq -r .result.root_pane.pane_id)
   herdr agent start <name> --kind claude --pane "$pane" -- "Read <handoff-file> and continue the work."
   ```

4. Tell the user which tab continues the work, then stop. Do not close your own tab.
