# Handoff — skills-plugins-reorg-wayfinder

_Session: "Reduce & reorganize skills and plugins (Wayfinder charting)" · 2026-07-20 · repo `marcuslannister/agent-scripts` (public)_

## Next session focus

Work the Wayfinder map's frontier. Recommended: run the **Prune audit** (research/AFK, the "give me advice" deliverable). The **Author taxonomy** (HITL grilling) is also unblocked.

## What this is

A Wayfinder map charts how to (1) group the 86 repo skills by author and (2) prune skills + installed plugins. Finish line = **plan + advice**; **execution is out of scope** for this map.

- Map: <https://github.com/marcuslannister/agent-scripts/issues/23> (`wayfinder:map`) — read the body for Destination / Decisions-so-far / fog. Do not restate it here.

## Done this session

- Charted the map + 3 child tickets, wired sub-issues + native `blocked_by`.
- Resolved linchpin <https://github.com/marcuslannister/agent-scripts/issues/24> → **real per-author subfolders are NOT viable** (Claude Code, Codex, and the topology adapter all discover skills flat). Full evidence in the issue's resolution comment. Closed.
- Redrew the destination grouping to **metadata + index** (an `author` field on `skill-topology.json` sources + a new `steipete` source + generated `INDEX.md`; `skills/` stays flat). Reframed ticket #26 to match.

## Frontier (both open, unblocked, unclaimed)

- <https://github.com/marcuslannister/agent-scripts/issues/25> — Prune audit: which skills + plugins to cut. Also confirm the "matt → claude+codex" item (looks already satisfied). **Recommended next.**
- <https://github.com/marcuslannister/agent-scripts/issues/26> — Author taxonomy: author values + per-skill assignment rule (metadata framing).

## How to continue (repo Wayfinding ops)

- Full mechanics: `docs/agents/issue-tracker.md` → "Wayfinding operations".
- Claim before any work: `gh issue edit <n> --add-assignee @me`.
- Resolve: comment the answer → `gh issue close <n>` → append a one-line pointer to the map's Decisions-so-far.
- One HITL ticket per session; research tickets are exempt.

## Guardrails specific to here

- **Planning only** — produce decisions, not moves/prunes/manifest edits.
- **Public repo** — issue bodies via `--body-file` (temp file, inspect first); relative paths only (no local home paths / usernames); no secrets.
- Edit an issue body by fetching via REST first: `gh api repos/OWNER/REPO/issues/<n> | jq -r '.body // ""' > /tmp/x.md`, inspect, then `--body-file`.
- Don't spawn subagents unless the user asks.
- Topology reality (gates any reorg): discovery is flat — `scripts/distribution-topology/adapters/repo-owned.sh` globs `skills/*/SKILL.md` and skips nested paths; see ADR-0001 / ADR-0002 under `docs/adr/`.

## Repo state at handoff

- Branch `main`, up to date with origin. `AGENTS.MD` clean (a stray de-bulleted line was restored this session).
- Untracked (pre-existing, not this map's concern): `skills/onecli-gateway/`, `skills/onecli-run/`, `skills/onecli-run-workspace/`. `onecli-run-workspace/` is skill-creator eval scaffolding (no top-level `SKILL.md`).
- Topology was reconciled this session (waza 3.31.2 → 3.32.0, a local plugin update); `--check` reports clean.

## Suggested skills for the next session

- `/wayfinder <ticket-url>` — work a frontier ticket (the driver for this whole effort).
- `/research` — resolve the Prune audit (#25): read each skill's `SKILL.md` + installed plugins, flag duplicates/unused/redundant.
- `/skill-cleaner` — skill audit heuristics (duplicates, compact descriptions) useful for #25.
- `/grilling` + `/domain-modeling` — resolve the Author taxonomy (#26).
