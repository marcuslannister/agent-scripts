---
name: context-audit
description: Audit and cut the startup context of Claude Code, Codex, or Pi (subagents, skills, MCP servers, plugin hooks, compaction). Use only when the user types /context-audit.
disable-model-invocation: true
---

# Context audit

Cut what every session loads before the first prompt. Each lever below
removes a cost that the agent pays on every turn, whether the material
fires or not. A lever is done when the measured number goes down and
the thing it removed still works by hand (`/name`, a project config).

## Steps

1. **Baseline.** Measure each CLI in scope before you change anything.
   Write down the numbers. Done when every CLI in scope has a number.
   - Claude Code: the user runs `/context`; record the total and the
     custom agents, skills, MCP tools, and memory files lines.
   - Codex: `cd /tmp && codex exec --skip-git-repo-check "reply OK" < /dev/null`,
     then read `total_token_usage.input_tokens` of the first
     `"type":"token_count"` event in the newest
     `~/.codex/sessions/<date>/rollout-*.jsonl`. Run it three times;
     one run can be about 1k higher.
   - Pi: `cd /tmp && pi -p "reply OK"`; read the first-turn prompt tokens.
2. **Inventory.** For each surface in "Levers", list what loads and its
   use in the last 90 days (session logs, the memory system). Done when
   each item is marked keep, manual-only, or remove.
3. **Apply.** One lever per commit, in the settings repo that owns the
   file (`claude-code-settings`, `codex-settings`, `pi-settings`,
   `agent-scripts`). Add a CHANGELOG line with the before and after
   numbers. When the live file is not the repo file (an ignored
   `~/.codex/config.toml`, or a `~/.claude` that is a real folder),
   change the repo file and the live file the same way.
4. **Measure again** with the method of step 1. Done when each lever
   shows its own drop, or you can say why it has none (a
   compaction-only change does not show in the first turn).
5. **Record.** Save the numbers and any new trap in the memory
   system of this machine. When another machine must follow, write a
   handoff `~/Projects/agent-scripts/handoff-<topic>.md` with the
   steps for that machine:
   a `git pull` does not change ignored live files such as
   `~/.codex/config.toml`.

## Levers

### Subagents

Remove the subagents with no calls in 90 days. Keep the ones a skill
names (`Explore`, `implementer`, `reviewer` for `/architect`).
Claude Code: `~/.claude/agents/`; 783 → 135 tokens on 2026-11-20.

### Skills

Make a skill manual-only when only a human types it. Its description
then leaves the startup context, and `/name` still works.

- Claude Code, own and built-in skills: `skillOverrides` in
  `settings.json`, value `user-invocable-only`. 4.7k → 2.5k tokens.
- Claude Code, plugin skills: `skillOverrides` does not reach them. A
  SessionStart hook writes `disable-model-invocation: true` into the
  installed frontmatter and reapplies it after a plugin update
  (`hooks/ponytail-lean.sh`).
- Codex reads `policy.allow_implicit_invocation: false` in
  `agents/openai.yaml`, not `disable-model-invocation`.
  `global/bin/install-skills.sh` writes that file for own skills.
- Pi reads `disable-model-invocation` from `~/.agents/skills`.

### MCP servers

Load a server only where it has data. The codegraph server is useful
only in a repo with `.codegraph/`: put it in that project's config
(Codex: `.codex/config.toml`, which loads only in a trusted project;
add `.codex/` to `.git/info/exclude`). Other indexed repos use the
`codegraph explore` CLI. Claude Code reads MCP config at process
start: restart, then check with `/mcp`.

### Plugin hooks that inject context

Nowledge Mem injects a Context Bundle (about 6.4 KB) at start and text
at each prompt. The lean patches swap it for a one-line search note:
`hooks/nowledge-lean.sh` (Claude Code) and
`agent-tooling/nowledge-lean-codex-pi.sh` (Codex with
`NOWLEDGE_LEAN_CODEX=1`, Pi by default). `NMEM_FULL_CONTEXT=1`
restores the full output. Each patch exits 1 when the upstream anchor
changes, so a plugin update cannot apply it half.

Codex trusts a plugin by a hash of its whole content. Patch first,
then approve the hooks once in a Codex TUI (`t`), started outside
herdr. In the other order every hook of the plugin fails, and Codex
sessions are not saved to Mem.

Remove hook entries of removed plugins (the old `claude-mem`
`[hooks.state]` entries in Codex).

### Always-loaded rules

Claude Code loads every file in `~/.claude/rules/` at startup. Keep
topic rules in `~/.claude/agent-rules/` behind a pointer line, and
import only the rules that apply to almost every reply. Codex and Pi
do not expand `@` imports: they read the generated
`global/AGENTS.codex.md`. A missing rule there is a fix that adds
tokens on purpose.

### Compaction and handoff

These do not change the first turn; they keep long sessions lean.

- Claude Code: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=65` in `settings.json`.
- Codex: `model_auto_compact_token_limit = 650000`.
- Pi: `compaction.modelOverrides["provider/id"].reserveTokens`; Pi
  compacts when `contextTokens > contextWindow - reserveTokens`.
- Handoff to a new herdr tab at 36% fill: `hooks/context-handoff.sh`
  in Claude Code, which points to `agent-rules/handoff.md`.

## Limited PC (Windows 11, Git Bash)

- No `home` repo: use the paths in `agent-scripts` and the settings
  repos only.
- Memory is agentmemory, not Nowledge Mem. Skip the Nowledge lever
  and the Codex hook approval that goes with it.
- `~/.claude` is a real folder, so `claude-code-settings` hooks and
  `settings.json` reach it only when you copy them. Change the live
  file, and the repo file only when every machine needs the change.
- Before a script that calls `python3`, run `python3 --version`. A
  Microsoft Store stub prints no version: stop and tell the user.
- `herdr` may be missing. Then the 36% handoff hook does not fire;
  that is expected.

## Traps

- `codex exec` waits on stdin: add `< /dev/null`.
- Codex `multi_agent` is deprecated; use `multi_agent_v2 = true`.
- A config check can print secrets (MCP bearer tokens, proxy
  credentials) into the transcript. Read only the keys you need.
- Compare a number only with a number from the same method. Claude
  Code `/context` and Codex session tokens count different things.

## History

Claude Code: 2026-11-18..20, `claude-code-settings/CHANGELOG.md`.
Codex and Pi: 2026-11-22, `codex-settings/CHANGELOG.md` and
`pi-settings/CHANGELOG.md`.
