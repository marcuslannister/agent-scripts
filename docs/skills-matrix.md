# Skills matrix

Every skill installed on this machine, both agents, one flat table. Generated once by scanning:

- **Claude:** `skills/` (repo) + every installed plugin under `~/.claude/plugins/cache/`
- **Codex:** `~/.agents/skills/` + the Codex-native plugin cache under `~/.codex/plugins/cache/` (`waza`, `claude-mem` ship real Codex plugins, not `~/.agents/skills` copies — see `CONTEXT.md`)

**Skill** is the invocation name (plugin-namespaced, e.g. `claude-mem:babysit`, where the skill only exists behind a plugin). **Source** is the GitHub `owner/repo` it ships from — see the Repos table below for each URL. **Type** is `skill` (plain SKILL.md, any distribution channel) or `plugin` (ships inside a Claude/Codex marketplace plugin). **~Tokens** is `file size ÷ 4` on the installed `SKILL.md`, a rough proxy for its context cost — not an exact tokenizer count.

Out of scope: OpenAI's bundled Codex plugins (`openai-bundled`, `openai-curated-remote`, `chatgpt-global` — browser/visualize/sites/artifact-templates) and Claude's `typescript-lsp` (no SKILL.md, not skill-shaped). These aren't part of this repo's managed skill ecosystem.

118 skills total — 116 on Claude, 112 on Codex, 110 on both, 6 Claude-only, 2 Codex-only.

| Skill | Source | Type | Agent | ~Tokens |
|---|---|---|---|---|
| `aihot` | marcuslannister/agent-scripts | skill | claude, codex | ~1245 |
| `algorithmic-art` | marcuslannister/agent-scripts | skill | claude, codex | ~4934 |
| `brand-guidelines` | marcuslannister/agent-scripts | skill | claude, codex | ~559 |
| `canvas-design` | marcuslannister/agent-scripts | skill | claude, codex | ~2984 |
| `claude-api` | marcuslannister/agent-scripts | skill | claude, codex | ~18325 |
| `claude-automation-recommender` | anthropics/claude-plugins-official | plugin | claude | ~2709 |
| `claude-mem:babysit` | thedotmack/claude-mem | plugin | claude, codex | ~1088 |
| `claude-mem:cloud-sync` | thedotmack/claude-mem | plugin | claude, codex | ~1826 |
| `claude-mem:design-is` | thedotmack/claude-mem | plugin | claude, codex | ~4648 |
| `claude-mem:do` | thedotmack/claude-mem | plugin | claude, codex | ~508 |
| `claude-mem:how-it-works` | thedotmack/claude-mem | plugin | claude, codex | ~308 |
| `claude-mem:knowledge-agent` | thedotmack/claude-mem | plugin | claude, codex | ~616 |
| `claude-mem:learn-codebase` | thedotmack/claude-mem | plugin | claude, codex | ~225 |
| `claude-mem:make-plan` | thedotmack/claude-mem | plugin | claude, codex | ~788 |
| `claude-mem:mem-search` | thedotmack/claude-mem | plugin | claude, codex | ~1019 |
| `claude-mem:oh-my-issues` | thedotmack/claude-mem | plugin | claude, codex | ~2904 |
| `claude-mem:pathfinder` | thedotmack/claude-mem | plugin | claude, codex | ~1539 |
| `claude-mem:smart-explore` | thedotmack/claude-mem | plugin | claude, codex | ~2304 |
| `claude-mem:standup` | thedotmack/claude-mem | plugin | claude, codex | ~1659 |
| `claude-mem:timeline-report` | thedotmack/claude-mem | plugin | claude, codex | ~3172 |
| `claude-mem:version-bump` | thedotmack/claude-mem | plugin | claude, codex | ~1155 |
| `claude-mem:weekly-digests` | thedotmack/claude-mem | plugin | claude, codex | ~3530 |
| `claude-mem:what-the` | thedotmack/claude-mem | plugin | claude, codex | ~62 |
| `claude-mem:wowerpoint` | thedotmack/claude-mem | plugin | claude, codex | ~2208 |
| `codex-first` | marcuslannister/agent-scripts | skill | claude | ~896 |
| `codex:codex-cli-runtime` | openai/codex-plugin-cc | plugin | claude | ~774 |
| `codex:codex-result-handling` | openai/codex-plugin-cc | plugin | claude | ~433 |
| `codex:gpt-5-4-prompting` | openai/codex-plugin-cc | plugin | claude | ~911 |
| `create-cli` | marcuslannister/agent-scripts | skill | claude, codex | ~834 |
| `doc-coauthoring` | marcuslannister/agent-scripts | skill | claude, codex | ~3954 |
| `docx` | marcuslannister/agent-scripts | skill | claude, codex | ~1717 |
| `frontend-design` | anthropics/claude-plugins-official | plugin | claude, codex | ~2062 |
| `github-author-context` | marcuslannister/agent-scripts | skill | claude, codex | ~950 |
| `github-cache-hygiene` | marcuslannister/agent-scripts | skill | claude, codex | ~925 |
| `github-deep-review` | marcuslannister/agent-scripts | skill | claude, codex | ~1432 |
| `github-project-triage` | marcuslannister/agent-scripts | skill | claude, codex | ~3982 |
| `hv-analysis` | marcuslannister/agent-scripts | skill | claude, codex | ~2102 |
| `internal-comms` | marcuslannister/agent-scripts | skill | claude, codex | ~378 |
| `khazix-writer` | marcuslannister/agent-scripts | skill | claude, codex | ~2947 |
| `mac-maintenance` | marcuslannister/agent-scripts | skill | claude, codex | ~184 |
| `maintainer-orchestrator` | marcuslannister/agent-scripts | skill | codex | ~11236 |
| `markdown-converter` | marcuslannister/agent-scripts | skill | claude, codex | ~434 |
| `mattpocock-skills:ask-matt` | mattpocock/skills | plugin | claude, codex | ~2043 |
| `mattpocock-skills:batch-grill-me` | mattpocock/skills | plugin | claude, codex | ~408 |
| `mattpocock-skills:claude-handoff` | mattpocock/skills | plugin | claude, codex | ~320 |
| `mattpocock-skills:code-review` | mattpocock/skills | plugin | claude, codex | ~1663 |
| `mattpocock-skills:codebase-design` | mattpocock/skills | plugin | claude, codex | ~1520 |
| `mattpocock-skills:design-an-interface` | mattpocock/skills | plugin | claude, codex | ~842 |
| `mattpocock-skills:diagnosing-bugs` | mattpocock/skills | plugin | claude, codex | ~2118 |
| `mattpocock-skills:domain-modeling` | mattpocock/skills | plugin | claude, codex | ~821 |
| `mattpocock-skills:edit-article` | mattpocock/skills | plugin | claude, codex | ~188 |
| `mattpocock-skills:git-guardrails-claude-code` | mattpocock/skills | plugin | claude, codex | ~578 |
| `mattpocock-skills:grill-me` | mattpocock/skills | plugin | claude, codex | ~37 |
| `mattpocock-skills:grill-with-docs` | mattpocock/skills | plugin | claude, codex | ~61 |
| `mattpocock-skills:grilling` | mattpocock/skills | plugin | claude, codex | ~210 |
| `mattpocock-skills:handoff` | mattpocock/skills | plugin | claude, codex | ~220 |
| `mattpocock-skills:implement` | mattpocock/skills | plugin | claude, codex | ~108 |
| `mattpocock-skills:improve-codebase-architecture` | mattpocock/skills | plugin | claude, codex | ~1498 |
| `mattpocock-skills:loop-me` | mattpocock/skills | plugin | claude, codex | ~632 |
| `mattpocock-skills:migrate-to-shoehorn` | mattpocock/skills | plugin | claude, codex | ~698 |
| `mattpocock-skills:obsidian-vault` | mattpocock/skills | plugin | claude, codex | ~378 |
| `mattpocock-skills:prototype` | mattpocock/skills | plugin | claude, codex | ~694 |
| `mattpocock-skills:qa` | mattpocock/skills | plugin | claude, codex | ~1233 |
| `mattpocock-skills:request-refactor-plan` | mattpocock/skills | plugin | claude, codex | ~678 |
| `mattpocock-skills:research` | mattpocock/skills | plugin | claude, codex | ~199 |
| `mattpocock-skills:resolving-merge-conflicts` | mattpocock/skills | plugin | claude, codex | ~230 |
| `mattpocock-skills:scaffold-exercises` | mattpocock/skills | plugin | claude, codex | ~897 |
| `mattpocock-skills:setup-matt-pocock-skills` | mattpocock/skills | plugin | claude, codex | ~1715 |
| `mattpocock-skills:setup-pre-commit` | mattpocock/skills | plugin | claude, codex | ~565 |
| `mattpocock-skills:setup-ts-deep-modules` | mattpocock/skills | plugin | claude, codex | ~1882 |
| `mattpocock-skills:tdd` | mattpocock/skills | plugin | claude, codex | ~796 |
| `mattpocock-skills:teach` | mattpocock/skills | plugin | claude, codex | ~2374 |
| `mattpocock-skills:to-questionnaire` | mattpocock/skills | plugin | claude, codex | ~726 |
| `mattpocock-skills:to-spec` | mattpocock/skills | plugin | claude, codex | ~766 |
| `mattpocock-skills:to-tickets` | mattpocock/skills | plugin | claude, codex | ~1415 |
| `mattpocock-skills:triage` | mattpocock/skills | plugin | claude, codex | ~1628 |
| `mattpocock-skills:ubiquitous-language` | mattpocock/skills | plugin | claude, codex | ~1220 |
| `mattpocock-skills:wayfinder` | mattpocock/skills | plugin | claude, codex | ~2948 |
| `mattpocock-skills:wizard` | mattpocock/skills | plugin | claude, codex | ~1037 |
| `mattpocock-skills:writing-beats` | mattpocock/skills | plugin | claude, codex | ~1216 |
| `mattpocock-skills:writing-fragments` | mattpocock/skills | plugin | claude, codex | ~890 |
| `mattpocock-skills:writing-great-skills` | mattpocock/skills | plugin | claude, codex | ~2332 |
| `mattpocock-skills:writing-shape` | mattpocock/skills | plugin | claude, codex | ~1482 |
| `mcp-builder` | marcuslannister/agent-scripts | skill | claude, codex | ~2265 |
| `nano-banana-pro` | marcuslannister/agent-scripts | skill | claude, codex | ~1454 |
| `native-app-performance` | marcuslannister/agent-scripts | skill | claude, codex | ~486 |
| `neat-freak` | marcuslannister/agent-scripts | skill | claude, codex | ~1903 |
| `obsidian` | marcuslannister/agent-scripts | skill | claude, codex | ~916 |
| `onecli-gateway` | onecli (no public repo) | skill | codex | ~1891 |
| `openai-image-gen` | marcuslannister/agent-scripts | skill | claude, codex | ~248 |
| `pdf` | marcuslannister/agent-scripts | skill | claude, codex | ~2009 |
| `peekaboo` | steipete/Peekaboo | skill | claude, codex | ~734 |
| `pptx` | marcuslannister/agent-scripts | skill | claude, codex | ~5162 |
| `release-mac-app` | marcuslannister/agent-scripts | skill | claude, codex | ~1666 |
| `remember` | anthropics/claude-plugins-official | plugin | claude | ~343 |
| `reminders` | marcuslannister/agent-scripts | skill | claude, codex | ~661 |
| `remote-mac` | marcuslannister/agent-scripts | skill | claude, codex | ~1707 |
| `review-claudemd` | marcuslannister/agent-scripts | skill | claude, codex | ~884 |
| `skill-cleaner` | marcuslannister/agent-scripts | skill | claude, codex | ~1046 |
| `skill-creator` | anthropics/claude-plugins-official | plugin | claude, codex | ~8247 |
| `slack-gif-creator` | marcuslannister/agent-scripts | skill | claude, codex | ~1960 |
| `ssh-doctor` | marcuslannister/agent-scripts | skill | claude, codex | ~1221 |
| `storage-analyzer` | marcuslannister/agent-scripts | skill | claude, codex | ~1398 |
| `theme-factory` | marcuslannister/agent-scripts | skill | claude, codex | ~781 |
| `validate-skills` | marcuslannister/agent-scripts | skill | claude, codex | ~231 |
| `video-transcript-downloader` | marcuslannister/agent-scripts | skill | claude, codex | ~558 |
| `visual-explainer` | nicobailon/visual-explainer | plugin | claude, codex | ~1684 |
| `waza:check` | tw93/Waza | plugin | claude, codex | ~10617 |
| `waza:health` | tw93/Waza | plugin | claude, codex | ~6320 |
| `waza:hunt` | tw93/Waza | plugin | claude, codex | ~4572 |
| `waza:learn` | tw93/Waza | plugin | claude, codex | ~2440 |
| `waza:read` | tw93/Waza | plugin | claude, codex | ~2106 |
| `waza:think` | tw93/Waza | plugin | claude, codex | ~3854 |
| `waza:ui` | tw93/Waza | plugin | claude, codex | ~5058 |
| `waza:write` | tw93/Waza | plugin | claude, codex | ~5735 |
| `web-artifacts-builder` | marcuslannister/agent-scripts | skill | claude, codex | ~768 |
| `webapp-testing` | marcuslannister/agent-scripts | skill | claude, codex | ~965 |
| `xlsx` | marcuslannister/agent-scripts | skill | claude, codex | ~2136 |

## Repos

| Repo | URL |
|---|---|
| `marcuslannister/agent-scripts` | https://github.com/marcuslannister/agent-scripts |
| `anthropics/claude-plugins-official` | https://github.com/anthropics/claude-plugins-official |
| `thedotmack/claude-mem` | https://github.com/thedotmack/claude-mem |
| `openai/codex-plugin-cc` | https://github.com/openai/codex-plugin-cc |
| `mattpocock/skills` | https://github.com/mattpocock/skills |
| `tw93/Waza` | https://github.com/tw93/Waza |
| `nicobailon/visual-explainer` | https://github.com/nicobailon/visual-explainer |
| `steipete/Peekaboo` | https://github.com/steipete/Peekaboo |

`onecli` (`onecli-gateway`) has no discoverable public GitHub repo — internal tool, `author: onecli` frontmatter tag only, no repo URL found.
