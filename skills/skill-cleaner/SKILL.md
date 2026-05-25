---
name: skill-cleaner
description: "Audit Codex/OpenClaw skills: loaded roots, duplicate skills, unused skills, prompt-budget costs, compact descriptions."
---

# Skill Cleaner

Use this when trimming skill prompt budget, finding duplicate skills, auditing enabled/disabled skill roots, or deciding which skills/plugins to remove.

## Workflow

1. Run the analyzer from this skill directory or repo root:

```bash
node --experimental-strip-types skills/skill-cleaner/scripts/skill-cleaner.ts --months 3
```

Useful variants:

```bash
node --experimental-strip-types skills/skill-cleaner/scripts/skill-cleaner.ts --no-logs
node --experimental-strip-types skills/skill-cleaner/scripts/skill-cleaner.ts --months 6 --max-log-mb 800 --deep-logs
```

2. Read the report in this order:
- `Description candidates`: long descriptions where relaxed grammar saves prompt budget.
- `Duplicates`: same skill name or near-identical description/body across Codex, plugin cache, repo siblings, and personal skill roots.
- `Unused candidates`: no recent `$skill` mention, `SKILL.md` read, or explicit skill-use trace in recent Codex/OpenClaw logs.
- `Root summary`: where skills came from and whether config marks them disabled.

3. Before deleting or editing:
- Verify the kept copy exists and is loaded.
- Prefer deleting repo-local or `agent-scripts` duplicates when Codex built-ins cover them.
- Keep repo-local OpenClaw maintainer skills when they encode repo policy or live operations.
- Preserve trigger nouns in descriptions: product, tool, action, object.

## Analyzer Notes

- The script mirrors Codex's model-visible line shape: `- name: description (file: path)`.
- It applies Codex-like frontmatter rules: YAML frontmatter only, default name from parent dir, single-line sanitized `name` and `description`.
- It approximates Codex description budgeting with rendered line chars/bytes. For exact behavior, inspect `codex-rs/core-skills/src/render.rs`.
- It scans `~/.codex/history.jsonl` and recent `~/.codex/sessions/**/*.jsonl` by default. Add `--deep-logs` for archived sessions and common OpenClaw/Clawd log folders.
- Usage evidence is heuristic: `$skill`, `Use $skill`, and paths like `skills/<name>/SKILL.md`.

## Output Policy

- Suggest first; edit only when the user asks.
- If asked to apply cleanup, make small grouped commits: descriptions, deletes, config disables.
- Do not delete ignored/untracked skill dirs without naming the destination or confirming they are disposable.
