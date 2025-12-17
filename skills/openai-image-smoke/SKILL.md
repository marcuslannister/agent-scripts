---
name: openai-image-smoke
description: Quick smoke-test for OpenAI image models. Generates a batch of random prompts, saves PNGs + a tiny `index.html` gallery.
---

# OpenAI Image Smoke

Generate a handful of “random but structured” prompts and render them via OpenAI Images API.

## Setup

- Needs env: `OPENAI_API_KEY`

## Run

From any directory (outputs to `~/Projects/tmp/...` when present; else `./tmp/...`):

```bash
python3 ~/Projects/agent-scripts/skills/openai-image-smoke/scripts/smoke.py
open ~/Projects/tmp/openai-image-smoke-*/index.html
```

Useful flags:

```bash
python3 ~/Projects/agent-scripts/skills/openai-image-smoke/scripts/smoke.py --count 16 --model gpt-image-1.5
python3 ~/Projects/agent-scripts/skills/openai-image-smoke/scripts/smoke.py --prompt "ultra-detailed studio photo of a lobster astronaut" --count 4
python3 ~/Projects/agent-scripts/skills/openai-image-smoke/scripts/smoke.py --size 1536x1024 --quality high --out-dir ./out/images-smoke
```

## Output

- `*.png` images
- `prompts.json` (prompt ↔ file mapping)
- `index.html` (thumbnail gallery)
