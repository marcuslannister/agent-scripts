#!/usr/bin/env python3
"""Regenerate the skill/plugin table in docs/skills-matrix.md.

Combines manifest-selected destinations with repo and staged inventories.
Installed plugin caches supply plugin skill names, token sizes, and enable
state. Prints the generated matrix sections to stdout.
"""
import os, glob, json, re
from collections import Counter

HOME = os.path.expanduser("~")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELF = "marcuslannister/agent-scripts"
UPSTREAM_MIRROR = "steipete/agent-scripts"

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

manifest = load_json(f"{REPO}/skill-topology.json")
manifest_sources = {source["id"]: source for source in manifest.get("sources", [])}
if not manifest_sources:
    raise SystemExit(f"missing or invalid topology manifest: {REPO}/skill-topology.json")

def selected_agents(source_id, skill):
    source = manifest_sources.get(source_id, {})
    return set(source.get("overrides", {}).get(skill, source.get("defaultDestinations", [])))

def toks(path):
    with open(path, "r", errors="ignore") as f:
        data = f.read()
    return max(1, round(len(data) / 4))

def basename(p):
    return os.path.basename(os.path.dirname(p))

rows = {}  # display name -> dict(source, type, claude, codex, tokens)

def add(display, source, typ, agents, path):
    t = toks(path)
    if display not in rows:
        rows[display] = {"source": source, "type": typ, "claude": False, "codex": False, "tokens": t}
    elif source == UPSTREAM_MIRROR:
        rows[display]["source"] = source
        rows[display]["type"] = typ
    for agent in agents:
        rows[display][agent] = True
    rows[display]["tokens"] = max(rows[display]["tokens"], t)

# --- Codex copies/native caches provide token paths for selected plugin rows ---
codex_paths = glob.glob(f"{HOME}/.agents/skills/*/SKILL.md")
codex_names = {basename(p): p for p in codex_paths}

# dual-plugin sources (waza, claude-mem) distribute to Codex via Codex's OWN
# native plugin cache, not ~/.agents/skills -- merge those names in too.
for p in glob.glob(f"{HOME}/.codex/plugins/cache/waza/waza/*/skills/*/SKILL.md"):
    codex_names.setdefault(basename(p), p)
for p in glob.glob(f"{HOME}/.codex/plugins/cache/claude-mem-local/claude-mem/*/skills/*/SKILL.md"):
    codex_names.setdefault(basename(p), p)

# repo name -> GitHub URL, for the Repos table
REPO_URLS = {
    "marcuslannister/agent-scripts": "https://github.com/marcuslannister/agent-scripts",
    "anthropics/claude-plugins-official": "https://github.com/anthropics/claude-plugins-official",
    "anthropics/skills": "https://github.com/anthropics/skills",
    "KKKKhazix/khazix-skills": "https://github.com/KKKKhazix/khazix-skills",
    "thedotmack/claude-mem": "https://github.com/thedotmack/claude-mem",
    "openai/codex-plugin-cc": "https://github.com/openai/codex-plugin-cc",
    "mattpocock/skills": "https://github.com/mattpocock/skills",
    "tw93/Waza": "https://github.com/tw93/Waza",
    "nicobailon/visual-explainer": "https://github.com/nicobailon/visual-explainer",
    "steipete/agent-scripts": "https://github.com/steipete/agent-scripts",
    "steipete/Peekaboo": "https://github.com/steipete/Peekaboo",
}
NO_REPO_SOURCES = {"onecli (no public repo)"}

# --- claude plugin sources (version dirs matched via glob, not pinned) ---
PLUGIN_SOURCES = [
    ("codex", f"{HOME}/.claude/plugins/cache/openai-codex/codex/*", "openai/codex-plugin-cc", "openai-codex", "codex"),
    ("claude-mem", f"{HOME}/.claude/plugins/cache/thedotmack/claude-mem/*", "thedotmack/claude-mem", "claude-mem", "claude-mem"),
    ("waza", f"{HOME}/.claude/plugins/cache/waza/waza/*/skills", "tw93/Waza", "waza", "waza"),
    ("mattpocock-skills", f"{HOME}/.claude/plugins/cache/mattpocock/mattpocock-skills/*", "mattpocock/skills", "matt-plugin", "mattpocock-skills"),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/claude-code-setup/*", "anthropics/claude-plugins-official", None, None),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/remember/*", "anthropics/claude-plugins-official", None, None),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/frontend-design/*", "anthropics/claude-plugins-official", None, None),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/skill-creator/*", "anthropics/claude-plugins-official", None, None),
]

for ns, root_glob, source, source_id, selection_skill in PLUGIN_SOURCES:
    for root in glob.glob(root_glob):
        for p in glob.glob(f"{root}/**/SKILL.md", recursive=True):
            name = basename(p)
            display = f"{ns}:{name}" if ns else name
            agents = selected_agents(source_id, selection_skill) if source_id else {"claude"}
            if source_id == "matt-plugin":
                agents |= selected_agents("matt-skills", name)
            add(display, source, "plugin", agents, codex_names.get(name, p) if "codex" in agents else p)

# visual-explainer plugin root IS the skill (no nested skills/ dir)
for root in glob.glob(f"{HOME}/.claude/plugins/cache/visual-explainer-marketplace/visual-explainer/*"):
    ve_path = f"{root}/SKILL.md"
    if os.path.exists(ve_path):
        agents = selected_agents("visual-explainer", "visual-explainer")
        add("visual-explainer", "nicobailon/visual-explainer", "plugin", agents, codex_names.get("visual-explainer", ve_path) if "codex" in agents else ve_path)

# --- tracked upstream mirror + repo-owned Codex authoring source ---
mirror_names = set()
for p in glob.glob(f"{REPO}/skills/*/SKILL.md"):
    name = basename(p)
    mirror_names.add(name)
    add(name, UPSTREAM_MIRROR, "skill", selected_agents("repo-claude", name), p)

for p in glob.glob(f"{REPO}/codex-skills/*/SKILL.md"):
    name = basename(p)
    add(name, SELF, "skill", selected_agents("repo-codex", name), p)

# --- staged source inventories; upstream mirror identity wins overlaps ---
STAGED_SOURCES = [
    ("anthropic-skills", "anthropics", "anthropics/skills"),
    ("khazix-skills", "marcus", "KKKKhazix/khazix-skills"),
]
for source_id, owner, source in STAGED_SOURCES:
    for p in glob.glob(f"{REPO}/other-skills/{owner}/*/SKILL.md"):
        name = basename(p)
        if name in mirror_names:
            continue
        add(name, source, "skill", selected_agents(source_id, name), p)

# Matt is a Claude plugin and a Codex copy selected from staging. Add a plain
# row only when the plugin cache did not already provide the namespaced row.
covered_basenames = {display.split(":")[-1] for display in rows}
for p in glob.glob(f"{REPO}/other-skills/matt/*/SKILL.md"):
    name = basename(p)
    if name in covered_basenames:
        continue
    add(name, "mattpocock/skills", "skill", selected_agents("matt-skills", name), p)

# markdown output
both = sum(1 for r in rows.values() if r["claude"] and r["codex"])
claude_only = sum(1 for r in rows.values() if r["claude"] and not r["codex"])
codex_only = sum(1 for r in rows.values() if r["codex"] and not r["claude"])
total_claude = sum(1 for r in rows.values() if r["claude"])
total_codex = sum(1 for r in rows.values() if r["codex"])

print("## Counts\n")
print("| Availability | Claude | Codex |")
print("|---|---|---|")
print(f"| Total | {total_claude} | {total_codex} |")
print(f"| Shared | {both} | {both} |")
print(f"| Agent-only | {claude_only} | {codex_only} |")

print("\n| Skill | Source | Type | Claude | Codex | ~Tokens |")
print("|---|---|---|---|---|---|")
for display in sorted(rows.keys()):
    r = rows[display]
    claude = "Y" if r["claude"] else "N"
    codex = "Y" if r["codex"] else "N"
    print(f"| `{display}` | {r['source']} | {r['type']} | {claude} | {codex} | ~{r['tokens']} |")

print(f"\n<!-- total={len(rows)} both={both} claude_only={claude_only} codex_only={codex_only} total_claude={total_claude} total_codex={total_codex} -->")

# --- enable-state: config truth on this machine (mutable, point-in-time) ---
CLAUDE_ENABLED = load_json(f"{HOME}/.claude/settings.json").get("enabledPlugins", {})
try:
    _cfg = open(f"{HOME}/.codex/config.toml").read()
except Exception:
    _cfg = ""
CODEX_ENABLED = {m.group(1): (m.group(2) == "true")
                 for m in re.finditer(r'\[plugins\."([^"]+)"\]\s*\nenabled\s*=\s*(true|false)', _cfg)}

# display namespace/name -> Claude plugin key in enabledPlugins
CLAUDE_PLUGIN_KEY = {
    "claude-mem": "claude-mem@thedotmack",
    "codex": "codex@openai-codex",
    "waza": "waza@waza",
    "mattpocock-skills": "mattpocock-skills@mattpocock",
    "frontend-design": "frontend-design@claude-plugins-official",
    "skill-creator": "skill-creator@claude-plugins-official",
    "visual-explainer": "visual-explainer@visual-explainer-marketplace",
    "claude-automation-recommender": "claude-code-setup@claude-plugins-official",
    "remember": "remember@claude-plugins-official",
}
# On Codex only Waza + claude-mem ship as native plugins; every other skill is a
# plain ~/.agents/skills copy with no enable toggle -> always-on.
CODEX_PLUGIN_KEY = {"waza": "waza@waza", "claude-mem": "claude-mem@claude-mem-local"}

def claude_state(display, typ):
    if typ != "plugin":
        return "always-on"
    key = CLAUDE_PLUGIN_KEY.get(display.split(":")[0]) or CLAUDE_PLUGIN_KEY.get(display)
    return "enabled" if CLAUDE_ENABLED.get(key) else "disabled"  # missing/False -> inactive

def codex_state(display):
    key = CODEX_PLUGIN_KEY.get(display.split(":")[0])
    if key is None:
        return "always-on"
    return "enabled" if CODEX_ENABLED.get(key) else "disabled"

c_state, z_state = Counter(), Counter()
for display, r in rows.items():
    if r["claude"]:
        c_state[claude_state(display, r["type"])] += 1
    if r["codex"]:
        z_state[codex_state(display)] += 1

print("\n## Enable-state\n")
print("Config truth on this machine, point-in-time (mutable — retoggling a plugin "
      "changes these). *Enabled/disabled* apply only to plugin-delivered skills — "
      "Claude reads `enabledPlugins` in `~/.claude/settings.json`, Codex reads "
      "`[plugins]` in `~/.codex/config.toml`. Plain `SKILL.md` copies have no "
      "toggle and are counted *always-on*. On Codex only Waza and claude-mem ship "
      "as native plugins; every other skill is an always-on `~/.agents/skills` "
      "copy. Claude Code's `/skills` picker reports fewer — it lists only "
      "enabled, plugin-*registered* skills (excluding disabled plugins, "
      "unregistered sub-skills in category folders, and plain copies), so "
      "this manifest-selected inventory runs higher.\n")
print("| State | Claude | Codex |")
print("|---|---|---|")
for label, key in (("Enabled", "enabled"), ("Disabled", "disabled"), ("Always-on", "always-on")):
    print(f"| {label} | {c_state[key]} | {z_state[key]} |")
print(f"| Total | {sum(c_state.values())} | {sum(z_state.values())} |")

print("\n## Repos\n")
print("| Repo | URL |")
print("|---|---|")
for repo in sorted({r["source"] for r in rows.values()} - NO_REPO_SOURCES):
    print(f"| `{repo}` | {REPO_URLS.get(repo, '?')} |")
for repo in sorted({r["source"] for r in rows.values()} & NO_REPO_SOURCES):
    print(f"\n`{repo}` — no discoverable public GitHub repo.")
