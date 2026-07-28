#!/usr/bin/env python3
"""Refresh matrix inventory and derived sections without changing selections."""

import glob
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass

sys.stdout.reconfigure(encoding="utf-8")

HOME = os.path.expanduser("~")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MATRIX = f"{REPO}/agent-tooling/skills-matrix.md"
SELF = "marcuslannister/agent-scripts"
UPSTREAM_MIRROR = "steipete/agent-scripts"


def load_json(path):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, ValueError):
        return {}


def github_repo(value):
    if not value:
        return None
    match = re.search(
        r"(?:https?://github\.com/|git@github\.com:)?"
        r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$",
        value.strip(),
    )
    return match.group(1) if match else None


def token_count(path):
    try:
        with open(path, "r", errors="ignore") as file:
            return max(1, round(len(file.read()) / 4))
    except OSError:
        return 1


@dataclass
class Row:
    display: str
    source: str
    delivery: str
    claude: str
    codex: str
    tokens: int
    claude_plugin_key: str | None = None
    codex_plugin_key: str | None = None


ROW_PATTERN = re.compile(
    r"^\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*"
    r"(skill|plugin)\s*\|\s*([YN])\s*\|\s*([YN])\s*\|\s*~?([0-9]+)\s*\|$"
)


def read_existing_rows():
    rows = {}
    try:
        with open(MATRIX, encoding="utf-8") as file:
            lines = file
            for raw_line in lines:
                match = ROW_PATTERN.match(raw_line.rstrip("\n"))
                if not match:
                    continue
                display, source, delivery, claude, codex, tokens = match.groups()
                rows[(display, delivery)] = Row(
                    display,
                    source.strip(),
                    delivery,
                    claude,
                    codex,
                    int(tokens),
                )
    except OSError:
        pass
    return rows


rows = read_existing_rows()


def merge_discovered(
    display,
    source,
    delivery,
    path,
    claude_plugin_key=None,
    codex_plugin_key=None,
):
    key = (display, delivery)
    existing = rows.get(key)
    if existing is None:
        existing = Row(display, source, delivery, "N", "N", token_count(path))
        rows[key] = existing
    else:
        existing.source = source
        existing.tokens = token_count(path)
    existing.claude_plugin_key = claude_plugin_key
    existing.codex_plugin_key = codex_plugin_key


def skill_name(path):
    return os.path.basename(os.path.dirname(path))


mirror_names = set()
for path in sorted(glob.glob(f"{REPO}/skills/*/SKILL.md")):
    name = skill_name(path)
    mirror_names.add(name)
    merge_discovered(name, UPSTREAM_MIRROR, "skill", path)

for path in sorted(glob.glob(f"{REPO}/codex-skills/*/SKILL.md")):
    name = skill_name(path)
    if name not in mirror_names:
        merge_discovered(name, SELF, "skill", path)

staged_names = set()
for path in sorted(glob.glob(f"{REPO}/other-skills/*/*/SKILL.md")):
    name = skill_name(path)
    if name in mirror_names or name in staged_names:
        continue
    staged_names.add(name)
    owner_root = os.path.dirname(os.path.dirname(path))
    owner = os.path.basename(owner_root)
    provenance = load_json(f"{owner_root}/.source.json")
    source = github_repo(provenance.get("repo")) or owner
    merge_discovered(name, source, "skill", path)

marketplaces = load_json(f"{HOME}/.claude/plugins/known_marketplaces.json")
marketplace_sources = {
    name: github_repo(value.get("source", {}).get("repo"))
    for name, value in marketplaces.items()
}
cache_root = f"{HOME}/.claude/plugins/cache"
for version_root in sorted(glob.glob(f"{cache_root}/*/*/*")):
    relative = os.path.relpath(version_root, cache_root).split(os.sep)
    if len(relative) != 3:
        continue
    marketplace, plugin_name, _version = relative
    paths = sorted(glob.glob(f"{version_root}/**/SKILL.md", recursive=True))
    source = marketplace_sources.get(marketplace) or marketplace
    for path in paths:
        name = plugin_name if os.path.dirname(path) == version_root else skill_name(path)
        display = name if len(paths) == 1 else f"{plugin_name}:{name}"
        merge_discovered(
            display,
            source,
            "plugin",
            path,
            f"{plugin_name}@{marketplace}",
            plugin_name,
        )


def selected(row, agent):
    return getattr(row, agent) == "Y"


all_rows = sorted(rows.values(), key=lambda row: (row.display, row.source, row.delivery))
both = sum(selected(row, "claude") and selected(row, "codex") for row in all_rows)
claude_only = sum(selected(row, "claude") and not selected(row, "codex") for row in all_rows)
codex_only = sum(selected(row, "codex") and not selected(row, "claude") for row in all_rows)
total_claude = both + claude_only
total_codex = both + codex_only

print("## Counts\n")
print("| Availability | Claude | Codex |")
print("|---|---|---|")
print(f"| Total | {total_claude} | {total_codex} |")
print(f"| Shared | {both} | {both} |")
print(f"| Agent-only | {claude_only} | {codex_only} |")

print("\n| Skill | Source | Type | Claude | Codex | ~Tokens |")
print("|---|---|---|---|---|---|")
for row in all_rows:
    print(
        f"| `{row.display}` | {row.source} | {row.delivery} | "
        f"{row.claude} | {row.codex} | ~{row.tokens} |"
    )

print(
    f"\n<!-- total={len(all_rows)} both={both} claude_only={claude_only} "
    f"codex_only={codex_only} total_claude={total_claude} total_codex={total_codex} -->"
)

claude_enabled = load_json(f"{HOME}/.claude/settings.json").get("enabledPlugins", {})
try:
    with open(f"{HOME}/.codex/config.toml", encoding="utf-8") as file:
        codex_config = file.read()
except OSError:
    codex_config = ""
codex_enabled = {
    match.group(1): match.group(2) == "true"
    for match in re.finditer(
        r'\[plugins\."([^"]+)"\]\s*\nenabled\s*=\s*(true|false)', codex_config
    )
}


def plugin_state(row, agent):
    if row.delivery == "skill":
        return "always-on"
    key = getattr(row, f"{agent}_plugin_key")
    if not key:
        return "disabled"
    enabled = claude_enabled if agent == "claude" else codex_enabled
    return "enabled" if enabled.get(key) else "disabled"


claude_state = Counter()
codex_state = Counter()
for row in all_rows:
    if selected(row, "claude"):
        claude_state[plugin_state(row, "claude")] += 1
    if selected(row, "codex"):
        codex_state[plugin_state(row, "codex")] += 1

print("\n## Enable-state\n")
print(
    "Config truth on this machine, point-in-time (mutable — retoggling a plugin "
    "changes these). *Enabled/disabled* apply only to native plugin-delivered "
    "skills; selected plain copies have no toggle and count as *always-on*. "
    "Claude Code's `/skills` picker reports fewer because it lists only enabled, "
    "plugin-registered skills, while this is the full selected inventory.\n"
)
print("| State | Claude | Codex |")
print("|---|---|---|")
for label, key in (
    ("Enabled", "enabled"),
    ("Disabled", "disabled"),
    ("Always-on", "always-on"),
):
    print(f"| {label} | {claude_state[key]} | {codex_state[key]} |")
print(f"| Total | {sum(claude_state.values())} | {sum(codex_state.values())} |")

print("\n## Repos\n")
print("| Repo | URL |")
print("|---|---|")
for source in sorted({row.source for row in all_rows}):
    repo = github_repo(source)
    url = f"https://github.com/{repo}" if repo else "?"
    print(f"| `{source}` | {url} |")
