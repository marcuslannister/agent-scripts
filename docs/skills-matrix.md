# Skills matrix

Every skill selected by the reconciled topology, plus installed plugin-only skills outside that topology, one flat table. Generated from:

- **Claude:** the tracked `skills/` mirror, staged inventories, manifest destinations, and installed plugins under `~/.claude/plugins/cache/`
- **Codex:** staged and repo-owned inventories selected by the manifest, plus Codex-native plugin caches under `~/.codex/plugins/cache/`

**Skill** is the invocation name (plugin-namespaced, e.g. `claude-mem:babysit`, where the skill only exists behind a plugin). **Source** is the GitHub `owner/repo` it ships from — see the Repos table below for each URL. **Type** is `skill` (plain SKILL.md, any distribution channel) or `plugin` (ships inside a Claude/Codex marketplace plugin). **Claude** and **Codex** are `Y`/`N` destination selections from reconciled manifest state; plugin-only rows outside the topology reflect installed cache availability. **~Tokens** is `file size ÷ 4` on the source `SKILL.md`, a rough proxy for its context cost — not an exact tokenizer count.

Out of scope: OpenAI's bundled Codex plugins (`openai-bundled`, `openai-curated-remote`, `chatgpt-global` — browser/visualize/sites/artifact-templates) and Claude's `typescript-lsp` (no SKILL.md, not skill-shaped). These aren't part of this repo's managed skill ecosystem.

## Counts

| Availability | Claude | Codex |
|---|---|---|
| Total | 147 | 107 |
| Shared | 107 | 107 |
| Agent-only | 40 | 0 |

| Skill | Source | Type | Claude | Codex | ~Tokens |
|---|---|---|---|---|---|
| `agent-transcript` | steipete/agent-scripts | skill | Y | N | ~1126 |
| `aihot` | KKKKhazix/khazix-skills | skill | Y | Y | ~1245 |
| `algorithmic-art` | anthropics/skills | skill | Y | Y | ~4934 |
| `beeper` | steipete/agent-scripts | skill | Y | N | ~250 |
| `brand-guidelines` | anthropics/skills | skill | Y | Y | ~559 |
| `browser-use` | steipete/agent-scripts | skill | Y | N | ~1288 |
| `canvas-design` | anthropics/skills | skill | Y | Y | ~2984 |
| `claude-api` | anthropics/skills | skill | Y | Y | ~17094 |
| `claude-automation-recommender` | anthropics/claude-plugins-official | plugin | Y | N | ~2709 |
| `claude-mem:babysit` | thedotmack/claude-mem | plugin | Y | Y | ~1088 |
| `claude-mem:cloud-sync` | thedotmack/claude-mem | plugin | Y | Y | ~1173 |
| `claude-mem:design-is` | thedotmack/claude-mem | plugin | Y | Y | ~4648 |
| `claude-mem:do` | thedotmack/claude-mem | plugin | Y | Y | ~508 |
| `claude-mem:how-it-works` | thedotmack/claude-mem | plugin | Y | Y | ~308 |
| `claude-mem:knowledge-agent` | thedotmack/claude-mem | plugin | Y | Y | ~616 |
| `claude-mem:learn-codebase` | thedotmack/claude-mem | plugin | Y | Y | ~225 |
| `claude-mem:make-plan` | thedotmack/claude-mem | plugin | Y | Y | ~788 |
| `claude-mem:mem-search` | thedotmack/claude-mem | plugin | Y | Y | ~1019 |
| `claude-mem:oh-my-issues` | thedotmack/claude-mem | plugin | Y | Y | ~2904 |
| `claude-mem:pathfinder` | thedotmack/claude-mem | plugin | Y | Y | ~1539 |
| `claude-mem:smart-explore` | thedotmack/claude-mem | plugin | Y | Y | ~2304 |
| `claude-mem:standup` | thedotmack/claude-mem | plugin | Y | Y | ~1659 |
| `claude-mem:timeline-report` | thedotmack/claude-mem | plugin | Y | Y | ~3172 |
| `claude-mem:version-bump` | thedotmack/claude-mem | plugin | Y | Y | ~1152 |
| `claude-mem:weekly-digests` | thedotmack/claude-mem | plugin | Y | Y | ~3530 |
| `claude-mem:what-the` | thedotmack/claude-mem | plugin | Y | Y | ~62 |
| `claude-mem:wowerpoint` | thedotmack/claude-mem | plugin | Y | Y | ~2208 |
| `clawsweeper-status` | steipete/agent-scripts | skill | Y | N | ~596 |
| `clickclack` | steipete/agent-scripts | skill | Y | N | ~711 |
| `cloudflare-registrar` | steipete/agent-scripts | skill | Y | N | ~372 |
| `codex-debugging` | steipete/agent-scripts | skill | Y | N | ~265 |
| `codex-first` | steipete/agent-scripts | skill | Y | N | ~3090 |
| `codex-huge-context` | steipete/agent-scripts | skill | Y | N | ~2574 |
| `codex:codex-cli-runtime` | openai/codex-plugin-cc | plugin | Y | N | ~774 |
| `codex:codex-result-handling` | openai/codex-plugin-cc | plugin | Y | N | ~433 |
| `codex:gpt-5-4-prompting` | openai/codex-plugin-cc | plugin | Y | N | ~911 |
| `create-cli` | steipete/agent-scripts | skill | Y | Y | ~834 |
| `discord-clawd` | steipete/agent-scripts | skill | Y | N | ~272 |
| `doc-coauthoring` | anthropics/skills | skill | Y | Y | ~3954 |
| `docx` | anthropics/skills | skill | Y | Y | ~1717 |
| `domain-dns-ops` | steipete/agent-scripts | skill | Y | N | ~679 |
| `fleet-maintenance` | steipete/agent-scripts | skill | Y | N | ~2905 |
| `frontend-design` | steipete/agent-scripts | skill | Y | N | ~2062 |
| `github-author-context` | steipete/agent-scripts | skill | Y | Y | ~950 |
| `github-cache-hygiene` | steipete/agent-scripts | skill | Y | Y | ~950 |
| `github-deep-review` | steipete/agent-scripts | skill | Y | Y | ~1432 |
| `github-project-triage` | steipete/agent-scripts | skill | Y | Y | ~3982 |
| `hopper-debugger` | steipete/agent-scripts | skill | Y | N | ~1200 |
| `hv-analysis` | KKKKhazix/khazix-skills | skill | Y | Y | ~2102 |
| `instruments-profiling` | steipete/agent-scripts | skill | Y | N | ~937 |
| `internal-comms` | anthropics/skills | skill | Y | Y | ~378 |
| `khazix-writer` | KKKKhazix/khazix-skills | skill | Y | Y | ~2947 |
| `mac-maintenance` | steipete/agent-scripts | skill | Y | Y | ~184 |
| `maintainer-orchestrator` | steipete/agent-scripts | skill | Y | N | ~11236 |
| `markdown-converter` | steipete/agent-scripts | skill | Y | Y | ~434 |
| `mattpocock-skills:ask-matt` | mattpocock/skills | plugin | Y | Y | ~2043 |
| `mattpocock-skills:batch-grill-me` | mattpocock/skills | plugin | Y | Y | ~408 |
| `mattpocock-skills:claude-handoff` | mattpocock/skills | plugin | Y | Y | ~320 |
| `mattpocock-skills:code-review` | mattpocock/skills | plugin | Y | Y | ~1663 |
| `mattpocock-skills:codebase-design` | mattpocock/skills | plugin | Y | Y | ~1520 |
| `mattpocock-skills:design-an-interface` | mattpocock/skills | plugin | Y | Y | ~842 |
| `mattpocock-skills:diagnosing-bugs` | mattpocock/skills | plugin | Y | Y | ~2118 |
| `mattpocock-skills:domain-modeling` | mattpocock/skills | plugin | Y | Y | ~821 |
| `mattpocock-skills:edit-article` | mattpocock/skills | plugin | Y | Y | ~188 |
| `mattpocock-skills:git-guardrails-claude-code` | mattpocock/skills | plugin | Y | Y | ~578 |
| `mattpocock-skills:grill-me` | mattpocock/skills | plugin | Y | Y | ~37 |
| `mattpocock-skills:grill-with-docs` | mattpocock/skills | plugin | Y | Y | ~61 |
| `mattpocock-skills:grilling` | mattpocock/skills | plugin | Y | Y | ~210 |
| `mattpocock-skills:handoff` | mattpocock/skills | plugin | Y | Y | ~220 |
| `mattpocock-skills:implement` | mattpocock/skills | plugin | Y | Y | ~108 |
| `mattpocock-skills:improve-codebase-architecture` | mattpocock/skills | plugin | Y | Y | ~1498 |
| `mattpocock-skills:loop-me` | mattpocock/skills | plugin | Y | Y | ~632 |
| `mattpocock-skills:migrate-to-shoehorn` | mattpocock/skills | plugin | Y | Y | ~698 |
| `mattpocock-skills:obsidian-vault` | mattpocock/skills | plugin | Y | Y | ~378 |
| `mattpocock-skills:prototype` | mattpocock/skills | plugin | Y | Y | ~694 |
| `mattpocock-skills:qa` | mattpocock/skills | plugin | Y | Y | ~1233 |
| `mattpocock-skills:request-refactor-plan` | mattpocock/skills | plugin | Y | Y | ~678 |
| `mattpocock-skills:research` | mattpocock/skills | plugin | Y | Y | ~199 |
| `mattpocock-skills:resolving-merge-conflicts` | mattpocock/skills | plugin | Y | Y | ~230 |
| `mattpocock-skills:scaffold-exercises` | mattpocock/skills | plugin | Y | Y | ~897 |
| `mattpocock-skills:setup-matt-pocock-skills` | mattpocock/skills | plugin | Y | Y | ~1715 |
| `mattpocock-skills:setup-pre-commit` | mattpocock/skills | plugin | Y | Y | ~565 |
| `mattpocock-skills:setup-ts-deep-modules` | mattpocock/skills | plugin | Y | Y | ~1882 |
| `mattpocock-skills:tdd` | mattpocock/skills | plugin | Y | Y | ~796 |
| `mattpocock-skills:teach` | mattpocock/skills | plugin | Y | Y | ~2374 |
| `mattpocock-skills:to-questionnaire` | mattpocock/skills | plugin | Y | Y | ~726 |
| `mattpocock-skills:to-spec` | mattpocock/skills | plugin | Y | Y | ~766 |
| `mattpocock-skills:to-tickets` | mattpocock/skills | plugin | Y | Y | ~1415 |
| `mattpocock-skills:triage` | mattpocock/skills | plugin | Y | Y | ~1628 |
| `mattpocock-skills:ubiquitous-language` | mattpocock/skills | plugin | Y | Y | ~1220 |
| `mattpocock-skills:wayfinder` | mattpocock/skills | plugin | Y | Y | ~2948 |
| `mattpocock-skills:wizard` | mattpocock/skills | plugin | Y | Y | ~1037 |
| `mattpocock-skills:writing-beats` | mattpocock/skills | plugin | Y | Y | ~1216 |
| `mattpocock-skills:writing-fragments` | mattpocock/skills | plugin | Y | Y | ~890 |
| `mattpocock-skills:writing-great-skills` | mattpocock/skills | plugin | Y | Y | ~2332 |
| `mattpocock-skills:writing-shape` | mattpocock/skills | plugin | Y | Y | ~1482 |
| `mcp-builder` | anthropics/skills | skill | Y | Y | ~2265 |
| `nano-banana-pro` | steipete/agent-scripts | skill | Y | Y | ~1411 |
| `native-app-performance` | steipete/agent-scripts | skill | Y | Y | ~486 |
| `neat-freak` | KKKKhazix/khazix-skills | skill | Y | Y | ~1903 |
| `notcrawl` | steipete/agent-scripts | skill | Y | N | ~272 |
| `npm` | steipete/agent-scripts | skill | Y | N | ~942 |
| `obsidian` | steipete/agent-scripts | skill | Y | Y | ~916 |
| `one-password` | steipete/agent-scripts | skill | Y | N | ~4714 |
| `openai-image-gen` | steipete/agent-scripts | skill | Y | Y | ~248 |
| `openclaw-relay` | steipete/agent-scripts | skill | Y | N | ~1207 |
| `oracle` | steipete/agent-scripts | skill | Y | N | ~2080 |
| `pdf` | anthropics/skills | skill | Y | Y | ~2009 |
| `peekaboo` | steipete/agent-scripts | skill | Y | Y | ~734 |
| `pptx` | anthropics/skills | skill | Y | Y | ~5162 |
| `release-mac-app` | steipete/agent-scripts | skill | Y | Y | ~1666 |
| `release-tweets` | steipete/agent-scripts | skill | Y | N | ~990 |
| `remember` | anthropics/claude-plugins-official | plugin | Y | N | ~343 |
| `reminders` | steipete/agent-scripts | skill | Y | Y | ~661 |
| `remote-mac` | steipete/agent-scripts | skill | Y | Y | ~2018 |
| `skill-cleaner` | steipete/agent-scripts | skill | Y | Y | ~1046 |
| `skill-creator` | anthropics/claude-plugins-official | plugin | Y | Y | ~8247 |
| `slack-gif-creator` | anthropics/skills | skill | Y | Y | ~1960 |
| `sonos` | steipete/agent-scripts | skill | Y | N | ~440 |
| `speaking` | steipete/agent-scripts | skill | Y | N | ~1159 |
| `ssh-doctor` | steipete/agent-scripts | skill | Y | Y | ~1221 |
| `storage-analyzer` | KKKKhazix/khazix-skills | skill | Y | Y | ~1398 |
| `swift-concurrency-expert` | steipete/agent-scripts | skill | Y | N | ~419 |
| `swiftui-liquid-glass` | steipete/agent-scripts | skill | Y | N | ~914 |
| `swiftui-performance-audit` | steipete/agent-scripts | skill | Y | N | ~1318 |
| `swiftui-view-refactor` | steipete/agent-scripts | skill | Y | N | ~1150 |
| `theme-factory` | anthropics/skills | skill | Y | Y | ~781 |
| `things-todo` | steipete/agent-scripts | skill | Y | N | ~710 |
| `twilio-sms` | steipete/agent-scripts | skill | Y | N | ~1060 |
| `video-transcript-downloader` | steipete/agent-scripts | skill | Y | Y | ~558 |
| `visual-explainer` | nicobailon/visual-explainer | plugin | Y | Y | ~1684 |
| `vm-lab` | steipete/agent-scripts | skill | Y | N | ~1554 |
| `waza:check` | tw93/Waza | plugin | Y | Y | ~10617 |
| `waza:health` | tw93/Waza | plugin | Y | Y | ~6320 |
| `waza:hunt` | tw93/Waza | plugin | Y | Y | ~4572 |
| `waza:learn` | tw93/Waza | plugin | Y | Y | ~2440 |
| `waza:read` | tw93/Waza | plugin | Y | Y | ~2106 |
| `waza:think` | tw93/Waza | plugin | Y | Y | ~3854 |
| `waza:ui` | tw93/Waza | plugin | Y | Y | ~5058 |
| `waza:write` | tw93/Waza | plugin | Y | Y | ~5735 |
| `web-artifacts-builder` | anthropics/skills | skill | Y | Y | ~768 |
| `webapp-testing` | anthropics/skills | skill | Y | Y | ~965 |
| `whatsapp` | steipete/agent-scripts | skill | Y | N | ~935 |
| `wrangler` | steipete/agent-scripts | skill | Y | N | ~488 |
| `xcode-sync` | steipete/agent-scripts | skill | Y | N | ~1236 |
| `xlsx` | anthropics/skills | skill | Y | Y | ~2136 |
| `xurl` | steipete/agent-scripts | skill | Y | N | ~841 |

<!-- total=147 both=107 claude_only=40 codex_only=0 total_claude=147 total_codex=107 -->

## Enable-state

Config truth on this machine, point-in-time (mutable — retoggling a plugin changes these). *Enabled/disabled* apply only to plugin-delivered skills — Claude reads `enabledPlugins` in `~/.claude/settings.json`, Codex reads `[plugins]` in `~/.codex/config.toml`. Plain `SKILL.md` copies have no toggle and are counted *always-on*. On Codex only Waza and claude-mem ship as native plugins; every other skill is an always-on `~/.agents/skills` copy. Claude Code's `/skills` picker reports fewer — it lists only enabled, plugin-*registered* skills (excluding disabled plugins, unregistered sub-skills in category folders, and plain copies), so this manifest-selected inventory runs higher.

| State | Claude | Codex |
|---|---|---|
| Enabled | 62 | 8 |
| Disabled | 12 | 18 |
| Always-on | 73 | 81 |
| Total | 147 | 107 |

## Repos

| Repo | URL |
|---|---|
| `KKKKhazix/khazix-skills` | https://github.com/KKKKhazix/khazix-skills |
| `anthropics/claude-plugins-official` | https://github.com/anthropics/claude-plugins-official |
| `anthropics/skills` | https://github.com/anthropics/skills |
| `mattpocock/skills` | https://github.com/mattpocock/skills |
| `nicobailon/visual-explainer` | https://github.com/nicobailon/visual-explainer |
| `openai/codex-plugin-cc` | https://github.com/openai/codex-plugin-cc |
| `steipete/agent-scripts` | https://github.com/steipete/agent-scripts |
| `thedotmack/claude-mem` | https://github.com/thedotmack/claude-mem |
| `tw93/Waza` | https://github.com/tw93/Waza |
