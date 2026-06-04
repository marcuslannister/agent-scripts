---
name: review-claudemd
description: Review recent conversations to find improvements for CLAUDE.md files.
---

# Review CLAUDE.md from conversation history

Analyze recent conversations to improve both global (~/.claude/CLAUDE.md) and local (project) CLAUDE.md files.

## Step 1: Find conversation history

The project's conversation history is in `~/.claude/projects/`. The folder name is the project path with slashes replaced by dashes.

```bash
# Find the project folder (path with / replaced by -)
PROJECT_PATH=${PWD//\//-}; PROJECT_PATH=${PROJECT_PATH#-}
CONVO_DIR=~/.claude/projects/-${PROJECT_PATH}
eza -1 --sort=modified --reverse "$CONVO_DIR"/*.jsonl | head -20
```

## Step 2: Extract recent conversations

Extract the 15-20 most recent conversations (excluding the current one) to a temp directory:

```bash
SCRATCH=/tmp/claudemd-review-$(date +%s)
mkdir -p "$SCRATCH"

for f in $(eza -1 --sort=modified --reverse "$CONVO_DIR"/*.jsonl | head -20); do
  basename=$(basename "$f" .jsonl)
  # Skip current conversation if known.
  # User content may be a string or an array of blocks — handle both.
  jq -r '
    if .type == "user" then
      "USER: " + (if (.message.content | type) == "string" then .message.content else ((.message.content // []) | map(select(.type == "text") | .text) | join("\n")) end)
    elif .type == "assistant" then
      "ASSISTANT: " + ((.message.content // []) | map(select(.type == "text") | .text) | join("\n"))
    else
      empty
    end
  ' "$f" 2>/dev/null | rg -v "^(ASSISTANT|USER): $" > "$SCRATCH/${basename}.txt"
done

eza -1 --sort=size --reverse "$SCRATCH"
```

## Step 3: Spin up Sonnet subagents

Launch parallel Sonnet subagents to analyze conversations. Each agent should read:
- Global CLAUDE.md: `~/.claude/CLAUDE.md`
- Local agent config: `./CLAUDE.md`, or `./AGENTS.md` if that's what the repo uses (some repos have one, not both)
- Batch of conversation files

Give each agent this prompt template:

```
Read:
1. Global CLAUDE.md: ~/.claude/CLAUDE.md
2. Local agent config: [project]/CLAUDE.md (or [project]/AGENTS.md if that's the one present)
3. Conversations: [list of files]

Analyze the conversations against BOTH config files. Find:
1. Instructions that exist but were violated (need reinforcement or rewording)
2. Patterns that should be added to the LOCAL file (project-specific)
3. Patterns that should be added to GLOBAL CLAUDE.md (applies everywhere)
4. Anything in either file that seems outdated or unnecessary

Be specific. Output bullet points only.
```

Batch conversations by size:
- Large (>100KB): 1-2 per agent
- Medium (10-100KB): 3-5 per agent
- Small (<10KB): 5-10 per agent

## Step 4: Aggregate findings

Combine results from all agents into a summary with these sections:

1. **Instructions violated** - existing rules that weren't followed (need stronger wording)
2. **Suggested additions - LOCAL** - project-specific patterns
3. **Suggested additions - GLOBAL** - patterns that apply everywhere
4. **Potentially outdated** - items that may no longer be relevant

Present as tables or bullet points. Ask user if they want edits drafted.
