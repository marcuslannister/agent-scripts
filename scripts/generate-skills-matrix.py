#!/usr/bin/env python3
"""Regenerate the skill/plugin table in docs/skills-matrix.md.

Combines the reconciler's selected-destination plan with repo and staged
inventories. Installed plugin caches supply plugin skill names, provenance,
token sizes, and enable state. Prints generated matrix sections to stdout.
"""
import glob
import json
import os
import re
import subprocess
from collections import Counter

HOME = os.path.expanduser("~")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELF = "marcuslannister/agent-scripts"
UPSTREAM_MIRROR = "steipete/agent-scripts"


def load_json(path):
    try:
        with open(path) as file:
            return json.load(file)
    except Exception:
        return {}


def github_repo(value):
    if not value:
        return None
    match = re.search(r"(?:https?://github\.com/|git@github\.com:)?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$", value.strip())
    return match.group(1) if match else None


def topology_plan():
    command = f"{REPO}/scripts/update-skill-topology.sh"
    result = subprocess.run([command, "--check", "--json"], text=True, capture_output=True)
    try:
        state = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(f"topology check did not return JSON: {error}") from error
    if result.returncode not in (0, 1, 3) or state.get("errors"):
        detail = "; ".join(state.get("errors", [])) or f"exit {result.returncode}"
        raise SystemExit(f"topology check failed: {detail}")
    return state.get("plan", [])


plan = topology_plan()
plan_agents = {
    (entry["sourceId"], entry["skill"]): set(entry.get("destinations", []))
    for entry in plan
}


def selected_agents(source_id, skill):
    return set(plan_agents.get((source_id, skill), ()))


def toks(path):
    with open(path, "r", errors="ignore") as file:
        return max(1, round(len(file.read()) / 4))


def skill_name(path):
    return os.path.basename(os.path.dirname(path))


rows = {}


def add(display, source, typ, agents, path, plugin_keys=None):
    token_count = toks(path)
    priority = 3 if source == UPSTREAM_MIRROR else (2 if typ == "plugin" else 1)
    if display not in rows:
        rows[display] = {
            "source": source,
            "type": typ,
            "claude": False,
            "codex": False,
            "tokens": token_count,
            "priority": priority,
            "claude_plugin_key": None,
            "codex_plugin_key": None,
        }
    if priority > rows[display]["priority"]:
        rows[display].update(
            source=source,
            type=typ,
            priority=priority,
            claude_plugin_key=None,
            codex_plugin_key=None,
        )
    if priority == rows[display]["priority"] and plugin_keys:
        rows[display]["claude_plugin_key"] = plugin_keys.get("claude")
        rows[display]["codex_plugin_key"] = plugin_keys.get("codex")
    for agent in agents:
        rows[display][agent] = True
    rows[display]["tokens"] = max(rows[display]["tokens"], token_count)


registry = load_json(f"{REPO}/scripts/distribution-topology/registry.json")
plugin_registry = {}
for entry in registry:
    plugin = entry.get("plugin")
    if not plugin:
        continue
    for agent, marketplace in plugin.get("marketplaces", {}).items():
        plugin_registry[(agent, marketplace, plugin["name"])] = entry

marketplaces = load_json(f"{HOME}/.claude/plugins/known_marketplaces.json")
marketplace_sources = {
    name: github_repo(value.get("source", {}).get("repo"))
    for name, value in marketplaces.items()
}

plugin_records = []
cache_root = f"{HOME}/.claude/plugins/cache"
for version_root in glob.glob(f"{cache_root}/*/*/*"):
    relative = os.path.relpath(version_root, cache_root).split(os.sep)
    if len(relative) != 3:
        continue
    marketplace, plugin_name, _version = relative
    paths = glob.glob(f"{version_root}/**/SKILL.md", recursive=True)
    if not paths:
        continue
    registration = plugin_registry.get(("claude", marketplace, plugin_name))
    source_id = registration["sourceId"] if registration else None
    plugin = registration.get("plugin", {}) if registration else {}
    source = marketplace_sources.get(marketplace) or github_repo(plugin.get("repo")) or marketplace
    bundle_agents = selected_agents(source_id, plugin_name) if source_id else {"claude"}
    plugin_keys = {"claude": f"{plugin_name}@{marketplace}"}
    codex_marketplace = plugin.get("marketplaces", {}).get("codex")
    if codex_marketplace and "codex" in bundle_agents:
        plugin_keys["codex"] = f"{plugin_name}@{codex_marketplace}"
    for path in paths:
        name = plugin_name if os.path.dirname(path) == version_root else skill_name(path)
        display = name if len(paths) == 1 else f"{plugin_name}:{name}"
        plugin_records.append(
            {
                "name": name,
                "display": display,
                "source": source,
                "agents": bundle_agents,
                "path": path,
                "plugin_keys": plugin_keys,
            }
        )

plugin_sources_by_name = {}
for record in plugin_records:
    plugin_sources_by_name.setdefault(record["name"], set()).add(record["source"])

skills_lock = load_json(f"{HOME}/.agents/.skill-lock.json").get("skills", {})


def staged_source(path, source_id, name):
    marker = f"{os.path.dirname(path)}/.agent-scripts-copy"
    if os.path.isfile(marker):
        with open(marker, errors="ignore") as file:
            source_path = file.readline().strip()
        if source_path:
            remote = subprocess.run(
                ["git", "-C", source_path, "remote", "get-url", "origin"],
                text=True,
                capture_output=True,
            )
            repo = github_repo(remote.stdout)
            if repo:
                return repo
    lock_entry = skills_lock.get(name, {})
    lock_source = lock_entry if isinstance(lock_entry, str) else lock_entry.get("source")
    repo = github_repo(lock_source)
    if repo:
        return repo
    plugin_sources = plugin_sources_by_name.get(name, set())
    if len(plugin_sources) == 1:
        return next(iter(plugin_sources))
    return source_id


plan_sources_by_skill = {}
plugin_source_ids = {entry["sourceId"] for entry in registry if entry.get("plugin")}
for source_id, name in plan_agents:
    if source_id not in {"repo-claude", "repo-codex"} and source_id not in plugin_source_ids:
        plan_sources_by_skill.setdefault(name, []).append(source_id)

staged_records = []
for path in glob.glob(f"{REPO}/other-skills/*/*/SKILL.md"):
    name = skill_name(path)
    marker = f"{os.path.dirname(path)}/.agent-scripts-copy"
    source_id = None
    if os.path.isfile(marker):
        with open(marker, errors="ignore") as file:
            file.readline()
            source_id = file.readline().strip() or None
    if source_id is None:
        candidates = plan_sources_by_skill.get(name, [])
        source_id = candidates[0] if len(candidates) == 1 else None
    if source_id is None:
        continue
    staged_records.append(
        {
            "name": name,
            "source": staged_source(path, source_id, name),
            "agents": selected_agents(source_id, name),
            "path": path,
        }
    )

mirror_names = set()
for path in glob.glob(f"{REPO}/skills/*/SKILL.md"):
    name = skill_name(path)
    mirror_names.add(name)
    add(name, UPSTREAM_MIRROR, "skill", selected_agents("repo-claude", name), path)

for path in glob.glob(f"{REPO}/codex-skills/*/SKILL.md"):
    name = skill_name(path)
    add(name, SELF, "skill", selected_agents("repo-codex", name), path)

staged_agents = {}
plugin_source_names = {(record["source"], record["name"]) for record in plugin_records}
for record in staged_records:
    if record["name"] in mirror_names:
        continue
    key = (record["source"], record["name"])
    staged_agents.setdefault(key, set()).update(record["agents"])
    if key not in plugin_source_names:
        add(record["name"], record["source"], "skill", record["agents"], record["path"])

for record in plugin_records:
    agents = set(record["agents"])
    agents.update(staged_agents.get((record["source"], record["name"]), ()))
    add(
        record["display"],
        record["source"],
        "plugin",
        agents,
        record["path"],
        record["plugin_keys"],
    )

both = sum(1 for row in rows.values() if row["claude"] and row["codex"])
claude_only = sum(1 for row in rows.values() if row["claude"] and not row["codex"])
codex_only = sum(1 for row in rows.values() if row["codex"] and not row["claude"])
total_claude = sum(1 for row in rows.values() if row["claude"])
total_codex = sum(1 for row in rows.values() if row["codex"])

print("## Counts\n")
print("| Availability | Claude | Codex |")
print("|---|---|---|")
print(f"| Total | {total_claude} | {total_codex} |")
print(f"| Shared | {both} | {both} |")
print(f"| Agent-only | {claude_only} | {codex_only} |")

print("\n| Skill | Source | Type | Claude | Codex | ~Tokens |")
print("|---|---|---|---|---|---|")
for display in sorted(rows):
    row = rows[display]
    claude = "Y" if row["claude"] else "N"
    codex = "Y" if row["codex"] else "N"
    print(f"| `{display}` | {row['source']} | {row['type']} | {claude} | {codex} | ~{row['tokens']} |")

print(f"\n<!-- total={len(rows)} both={both} claude_only={claude_only} codex_only={codex_only} total_claude={total_claude} total_codex={total_codex} -->")

claude_enabled = load_json(f"{HOME}/.claude/settings.json").get("enabledPlugins", {})
try:
    with open(f"{HOME}/.codex/config.toml") as file:
        codex_config = file.read()
except Exception:
    codex_config = ""
codex_enabled = {
    match.group(1): match.group(2) == "true"
    for match in re.finditer(r'\[plugins\."([^"]+)"\]\s*\nenabled\s*=\s*(true|false)', codex_config)
}


def plugin_state(key, enabled):
    if key is None:
        return "always-on"
    return "enabled" if enabled.get(key) else "disabled"


claude_state = Counter()
codex_state = Counter()
for row in rows.values():
    if row["claude"]:
        claude_state[plugin_state(row["claude_plugin_key"], claude_enabled)] += 1
    if row["codex"]:
        codex_state[plugin_state(row["codex_plugin_key"], codex_enabled)] += 1

print("\n## Enable-state\n")
print("Config truth on this machine, point-in-time (mutable — retoggling a plugin "
      "changes these). *Enabled/disabled* apply only to native plugin-delivered "
      "skills; selected plain copies have no toggle and count as *always-on*. "
      "Claude Code's `/skills` picker reports fewer because it lists only enabled, "
      "plugin-registered skills, while this is the full selected inventory.\n")
print("| State | Claude | Codex |")
print("|---|---|---|")
for label, key in (("Enabled", "enabled"), ("Disabled", "disabled"), ("Always-on", "always-on")):
    print(f"| {label} | {claude_state[key]} | {codex_state[key]} |")
print(f"| Total | {sum(claude_state.values())} | {sum(codex_state.values())} |")

print("\n## Repos\n")
print("| Repo | URL |")
print("|---|---|")
for source in sorted({row["source"] for row in rows.values()}):
    repo = github_repo(source)
    url = f"https://github.com/{repo}" if repo else "?"
    print(f"| `{source}` | {url} |")
