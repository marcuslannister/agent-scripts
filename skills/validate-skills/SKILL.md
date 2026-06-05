---
name: validate-skills
description: "Validate skill front matter: name, description, valid YAML, duplicate names."
---

# Validate Skills

Use before committing skill edits, or to check `skills/*/SKILL.md` front matter
on demand. Already runs automatically in `hooks/pre-commit` and
`scripts/committer`; this is the manual entry point.

## Run

From the agent-scripts repo (the script resolves the repo root itself):

```bash
scripts/validate-skills
```

Checks every `skills/*/SKILL.md` for a valid YAML front-matter mapping, non-empty
string `name` and `description`, and a `name` unique across skills.

- Exit 0: `Validated N skill(s).`
- Exit 1 (stderr): `Skill validation failed:` then `- <path>: <reason>` per problem.

Requires Python 3 with PyYAML (`pip install pyyaml`; add `--break-system-packages`
on an externally-managed Python).
