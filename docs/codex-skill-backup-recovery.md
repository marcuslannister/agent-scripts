---
summary: "Recover local-only skills from migrated Codex skill backups"
read_when:
  - Recovering entries from ~/.codex/skills-migrated-* backups.
  - Investigating Codex skill root drift after update-skill-topology.sh runs.
---

# Codex Skill Backup Recovery

Codex uses one supported skills root: `~/.agents/skills`. The old
`~/.codex/skills` root is legacy. `agent-tooling/update-skill-topology.sh` migrates
non-system entries from the legacy root into
`~/.codex/skills-migrated-<timestamp>` so Codex does not double-load skills.

After migration, `~/.codex/skills` should contain only Codex's bundled
`.system` entry when that entry exists. Tracked repo skills should be active as
marked copies under `~/.agents/skills/<skill>`.

## Inspect A Backup

Use the newest migrated backup first:

```bash
ls -la ~/.codex
find ~/.codex/skills-migrated-<timestamp> -maxdepth 2 -mindepth 1 -print
```

Each top-level backup entry is legacy drift. It is usually one of:

- a directory containing a skill, often with `SKILL.md`;
- a symlink to a skill directory;
- a plain pointer file containing a path to the old skill source.

Check whether an entry is already covered by the active surface before
restoring it:

```bash
name=<skill-name>
test -f ~/.agents/skills/$name/SKILL.md && echo "active already"
test -f ~/Projects/agent-scripts/skills/$name/SKILL.md && echo "tracked repo skill"
```

If the skill is tracked in this repo and approved for Codex, do not restore the
backup copy. Run `agent-tooling/update-skill-topology.sh`; it refreshes the active
managed copy from its declared source.

## Restore Local-Only Skills

Restore only a skill you intentionally keep outside this repo and outside a
skills CLI/plugin installer. Do not put it back under `~/.codex/skills`.

For a backup directory:

```bash
name=<skill-name>
src=~/.codex/skills-migrated-<timestamp>/$name
dst=~/.agents/skills/$name

test -f "$src/SKILL.md"
test ! -e "$dst"
mkdir -p ~/.agents/skills
cp -R "$src" "$dst"
```

For a plain pointer file, inspect the path first and restore the target skill,
not the pointer file itself:

```bash
name=<skill-name>
target=$(cat ~/.codex/skills-migrated-<timestamp>/$name)
test -f "$target/SKILL.md"
test ! -e ~/.agents/skills/$name
cp -R "$target" ~/.agents/skills/$name
```

Leave restored local-only skills unmarked. The updater owns only directories
with an `.agent-scripts-copy` marker that points back to this repo's
`skills/<name>` source.

## Verify

Run topology reconciliation after any restore:

```bash
~/Projects/agent-scripts/agent-tooling/update-skill-topology.sh
find ~/.codex/skills -maxdepth 1 -mindepth 1 ! -name .system -print
```

Topology reconciliation should finish green. The final `find` command should print
nothing.

If the command exits `3`, run `agent-tooling/update-skill-topology.sh --check --json`
and inspect `decisions`. A source, destination, collision, unknown plugin, or
unknown npx lock entry needs an explicit policy or installed-state decision.
Do not restore through the legacy root, guess a copy/plugin fallback, or delete
an unowned entry. Resolve the decision, then rerun reconciliation.

## Delete The Backup

Delete a migrated backup only after:

- you have inspected every top-level entry;
- every wanted local-only skill has been restored under `~/.agents/skills`;
- tracked repo skills are present as updater-managed marked copies;
- `agent-tooling/update-skill-topology.sh` finishes successfully;
- `~/.codex/skills` has no non-system entries.

Keep the backup if any entry is unclear. It is inactive while it stays under
`~/.codex/skills-migrated-<timestamp>`, so keeping it does not reintroduce
double-loading.
