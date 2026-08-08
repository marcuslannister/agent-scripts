---
status: accepted
---

# Oversized Codex marketplaces stay on manual repair

Codex's `plugin marketplace upgrade` does not fetch into the existing snapshot — it re-clones the whole source repository into `~/.codex/.tmp/marketplaces/.staging/` under a hardcoded 30-second timeout, then swaps (confirmed on `codex-cli` 0.147.0). `thedotmack/claude-mem` is ~330MB with history and takes ~44s to full-clone, so its Codex marketplace can never refresh: acquire fails with `fatal: early EOF`, the native verification gate for the `claude-mem` dual-plugin skill stays blocked, and its duplicate surface copies survive cleanup. The failure is deterministic, not transient, and recurs with every claude-mem release. Smaller marketplaces (Waza 4.5MB, visual-explainer 4.2MB) finish inside the window.

We are not automating a fix. The recovery stays a manual, documented procedure: fast-forward the snapshot with `git -C ~/.codex/.tmp/marketplaces/<name> fetch origin main && git merge --ff-only origin/main` (~1s, purely additive), run `codex plugin add <plugin>@<name>`, then hand-sync the two bookkeeping fields Codex would have written — `revision` in `.codex-marketplace-install.json`, and `last_revision` / `last_updated` under `[marketplaces.<name>]` in `~/.codex/config.toml`. This costs a few minutes per claude-mem release and touches nothing the repo owns.

The only code change is diagnostic. `upgrade_codex_marketplace` retried three times, two seconds apart, against a failure that cannot succeed on retry, turning one real problem into three identical errors. It now recognises the clone-timeout signature, stops after the first attempt, and prints one error naming the cause and this ADR. Failures that could be transient keep the full retry budget.

## Considered options

Two automated fixes were designed and rejected. The first was **native-state repair**: the private adapter performs the fetch itself and hand-writes Codex's snapshot, install metadata, and `config.toml` fields. It works, but it makes this repo permanently liable for three undocumented Codex-internal formats that are free to change between releases, and it puts a private adapter — defined as reconciling one manifest source *without owning policy* — in charge of another CLI's bookkeeping.

The second was an **adapter-owned marketplace clone**: keep a shallow clone under `~/.cache/agent-scripts/marketplaces/<sourceId>` and register it with Codex as a `source_type = "local"` marketplace, which removes the full clone from the picture entirely. This was implemented and tested before being dropped. It is sound, and it keeps every write to Codex state going through `codex` commands, but it buys automation of a few minutes per release in exchange for a permanent second code path in the plugin adapter, a per-machine cache directory that git never carries, and a destructive one-time migration — `codex plugin marketplace remove` drops the installed plugin and its `hooks.state` trusted hashes. The cost of the failure did not justify the standing complexity.

A third option, re-registering the git marketplace with `--sparse`, stays fully native and a sparse probe finishes in ~2.5s, but it is unverified whether later `upgrade` runs honour recorded `sparse_paths`, and finding out costs the same destructive re-registration.

## Consequences

Each claude-mem release blocks the Codex side of the native verification gate until someone runs the manual repair. Acquire now reports that as a single actionable error instead of three identical ones, but it is still a failure the operator must clear by hand.

Plugin-managed recovery is unchanged and, with no automation added, untested against a new case: reconciliation still never substitutes a surface copy for a failed plugin, and **native-state repair** remains named and rejected in the glossary.

The underlying Codex defect — a full clone under a hardcoded timeout with no configurable escape — should be reported upstream. An incremental fetch, a partial clone, or a timeout knob in Codex removes the problem at its source and is the outcome worth waiting for. If the manual repair becomes frequent enough to hurt, the adapter-owned local clone above is the fallback design, and it was proven workable.
