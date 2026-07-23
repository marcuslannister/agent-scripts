#!/usr/bin/env python3
"""Regenerate the skill/plugin table in docs/skills-matrix.md.

Scans installed Claude Code plugin caches, the repo's own skills/ and
codex-skills/ dirs, and Codex's ~/.agents/skills/ + native plugin cache to
list every skill both agents can see. Prints markdown to stdout; paste the
table + Repos section into docs/skills-matrix.md.
"""
import os, glob, json, re
from collections import Counter

HOME = os.path.expanduser("~")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def toks(path):
    with open(path, "r", errors="ignore") as f:
        data = f.read()
    return max(1, round(len(data) / 4))

def basename(p):
    return os.path.basename(os.path.dirname(p))

rows = {}  # display name -> dict(source, type, claude, codex, tokens)

def add(display, source, typ, agent, path):
    t = toks(path)
    if display not in rows:
        rows[display] = {"source": source, "type": typ, "claude": False, "codex": False, "tokens": t}
    rows[display][agent] = True
    rows[display]["tokens"] = max(rows[display]["tokens"], t)

# --- codex actual read root: ground truth for ALL codex skill names ---
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
    "thedotmack/claude-mem": "https://github.com/thedotmack/claude-mem",
    "openai/codex-plugin-cc": "https://github.com/openai/codex-plugin-cc",
    "mattpocock/skills": "https://github.com/mattpocock/skills",
    "tw93/Waza": "https://github.com/tw93/Waza",
    "nicobailon/visual-explainer": "https://github.com/nicobailon/visual-explainer",
    "steipete/Peekaboo": "https://github.com/steipete/Peekaboo",
}
NO_REPO_SOURCES = {"onecli (no public repo)"}

# --- claude plugin sources (version dirs matched via glob, not pinned) ---
PLUGIN_SOURCES = [
    ("codex", f"{HOME}/.claude/plugins/cache/openai-codex/codex/*", "openai/codex-plugin-cc"),
    ("claude-mem", f"{HOME}/.claude/plugins/cache/thedotmack/claude-mem/*", "thedotmack/claude-mem"),
    ("waza", f"{HOME}/.claude/plugins/cache/waza/waza/*/skills", "tw93/Waza"),
    ("mattpocock-skills", f"{HOME}/.claude/plugins/cache/mattpocock/mattpocock-skills/*", "mattpocock/skills"),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/claude-code-setup/*", "anthropics/claude-plugins-official"),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/remember/*", "anthropics/claude-plugins-official"),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/frontend-design/*", "anthropics/claude-plugins-official"),
    (None, f"{HOME}/.claude/plugins/cache/claude-plugins-official/skill-creator/*", "anthropics/claude-plugins-official"),
]

for ns, root_glob, source in PLUGIN_SOURCES:
    for root in glob.glob(root_glob):
        for p in glob.glob(f"{root}/**/SKILL.md", recursive=True):
            name = basename(p)
            display = f"{ns}:{name}" if ns else name
            add(display, source, "plugin", "claude", p)
            if name in codex_names:
                add(display, source, "plugin", "codex", codex_names[name])

# visual-explainer plugin root IS the skill (no nested skills/ dir)
for root in glob.glob(f"{HOME}/.claude/plugins/cache/visual-explainer-marketplace/visual-explainer/*"):
    ve_path = f"{root}/SKILL.md"
    if os.path.exists(ve_path):
        add("visual-explainer", "nicobailon/visual-explainer", "plugin", "claude", ve_path)
        if "visual-explainer" in codex_names:
            add("visual-explainer", "nicobailon/visual-explainer", "plugin", "codex", codex_names["visual-explainer"])

# --- claude repo skills/ ---
SELF = "marcuslannister/agent-scripts"
SELF_OVERRIDES = {"peekaboo": "steipete/Peekaboo"}
for p in glob.glob(f"{REPO}/skills/*/SKILL.md"):
    name = basename(p)
    source = SELF_OVERRIDES.get(name, SELF)
    add(name, source, "skill", "claude", p)
    if name in codex_names:
        add(name, source, "skill", "codex", codex_names[name])

# --- codex repo codex-skills/ ---
for p in glob.glob(f"{REPO}/codex-skills/*/SKILL.md"):
    name = basename(p)
    source = SELF_OVERRIDES.get(name, SELF)
    add(name, source, "skill", "codex", p)

# --- remaining codex-only names not yet captured (npx / source-only clones) ---
covered_basenames = {display.split(":")[-1] for display in rows}
FALLBACK_SOURCES = {"onecli-gateway": "onecli (no public repo)"}
for name, p in codex_names.items():
    if name in covered_basenames:
        continue
    add(name, FALLBACK_SOURCES.get(name, "mattpocock/skills"), "skill", "codex", p)

# markdown output
both = sum(1 for r in rows.values() if r["claude"] and r["codex"])
claude_only = sum(1 for r in rows.values() if r["claude"] and not r["codex"])
codex_only = sum(1 for r in rows.values() if r["codex"] and not r["claude"])
total_claude = sum(1 for r in rows.values() if r["claude"])
total_codex = sum(1 for r in rows.values() if r["codex"])

print("| Skill | Source | Type | Agent | ~Tokens |")
print("|---|---|---|---|---|")
for display in sorted(rows.keys()):
    r = rows[display]
    agent = "claude, codex" if r["claude"] and r["codex"] else ("claude" if r["claude"] else "codex")
    print(f"| `{display}` | {r['source']} | {r['type']} | {agent} | ~{r['tokens']} |")

print(f"\n<!-- total={len(rows)} both={both} claude_only={claude_only} codex_only={codex_only} total_claude={total_claude} total_codex={total_codex} -->")

# --- enable-state: config truth on this machine (mutable, point-in-time) ---
def _json(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception:
        return {}

CLAUDE_ENABLED = _json(f"{HOME}/.claude/settings.json").get("enabledPlugins", {})
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
      "copy.\n")
print("| Agent | Enabled | Disabled | Always-on | Total |")
print("|---|---|---|---|---|")
for label, s in (("Claude", c_state), ("Codex", z_state)):
    print(f"| {label} | {s['enabled']} | {s['disabled']} | {s['always-on']} | {sum(s.values())} |")

print("\n## Repos\n")
print("| Repo | URL |")
print("|---|---|")
for repo in sorted({r["source"] for r in rows.values()} - NO_REPO_SOURCES):
    print(f"| `{repo}` | {REPO_URLS.get(repo, '?')} |")
for repo in sorted({r["source"] for r in rows.values()} & NO_REPO_SOURCES):
    print(f"\n`{repo}` — no discoverable public GitHub repo.")
