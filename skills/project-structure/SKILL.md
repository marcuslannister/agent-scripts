---
name: project-structure
description: "Generate a single-file compressed symbol map of a TypeScript repository — files, exported symbols, typed signatures, plugin boundaries — sized to fit an LLM context window. Use for whole-project reasoning: duplication hunting, refactor planning, architecture recon, or feeding another agent a full-project map."
---

# Project Structure

Compress a TS repo into one map file an agent can load whole. Backed by `map.ts` next to this file (parse-only TS compiler, no type-check; ~8k files in ~5s). Requires Node >= 23.6 (native type stripping) or `npx tsx`; resolves the `typescript` package from the target repo, falling back to this skill dir.

## Run

```bash
node <this-skill-dir>/map.ts <repoRoot> [flags]
```

`<this-skill-dir>` is the base directory of this skill as announced when the skill loads (canonical: `~/Projects/agent-scripts/skills/project-structure`).

Output: one map file (default `project-structure-map.txt` in cwd) plus a JSON stats line (files, bytes, approxTokens) on stdout.

## Flags

- `--out <file>` — output path.
- `--mode dense|skeleton|exports|sigs|full` — default `dense`.
  - `dense`: dir-grouped, one line per file: `file fn:a,b ty:T cl:C c:x re:./y`. Recon tier.
  - `skeleton`: one symbol per line, names only.
  - `exports`: exported symbols with full typed signatures, type bodies, first doc-comment line. Refactor-decision tier.
  - `sigs`: exports but type/interface bodies collapsed to member names (only ~10% smaller than exports; rarely worth it).
  - `full`: exports + non-exported top-level symbols (marked `internal`).
- `--include a,b,c` — top-level dirs to map (default: all top-level dirs, minus skips/boundaries).
- `--boundary x,y` — dirs listed as boundary index only: child module names + one-line `package.json` descriptions, no symbol content. Use for plugin/extension trees.
- `--include-tests` — keep test files and test-support infra (default: both excluded).
- `--no-docs` — strip doc comments (saves ~13% on typed modes).
- `--fn-consts-only` — drop non-function const exports. Caution: silently drops files whose only exports are consts (plugin definition objects, schemas, registries). Prefer keeping consts in `dense` (names are cheap).
- `--re-counts` — collapse re-export path lists to a count (dense; saves ~10%).
- `--max-per-kind N` — cap each symbol-kind list per file with `+n` overflow marker (dense; 10–12 is safe).

## Sizing (reference: openclaw, ~7M LOC, ~14k source files; o200k tokens; byte/4 estimate runs ~5–15% high — verify with a real tokenizer when near a budget)

- exports, whole repo: ~2.5M tokens — never fits; scope typed maps to one subsystem.
- exports, one subsystem (e.g. src/channels, 257 files): ~79k.
- skeleton, whole repo: ~717k (fits 1M-class windows).
- dense, whole repo: ~430k real.
- dense, `src`+`packages` + extensions boundary, `--re-counts --max-per-kind 12`: ~218k real.
- dense, `src` only + boundaries, `--re-counts --max-per-kind 10`: ~197k real (fits a 200k window).

## Workflow guidance

- Two-tier: dense whole-repo map for reconnaissance and candidate enumeration; then `--mode exports --include <subsystem>` for the actual refactor decision. Names alone cannot distinguish duplicates from overloads, facades, or `.runtime.ts` lazy seams — verify every dense-tier finding against typed signatures or source before acting.
- Feeding codex CLI: turn input hard-caps at 1,048,576 chars (~260k tokens); pipe the map via stdin. Bigger maps need a direct Responses API call ($codex-huge-context) or a model with a larger window.
- Do not bother with dictionary/abbreviation compression: measured on openclaw, total possible savings were 292 tokens (0.15%) — BPE already compresses repeated identifiers.
- Map findings are leads, not verdicts: spot-verify file paths and claims with grep before acting on any model analysis of a map.
