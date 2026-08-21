---
status: accepted; routine automation no longer attempts marketplace operations (ADR-0009); the marker-only repair exception (`repair-claude-mem-marker.sh`) was removed with claude-mem's source entry
---

# Oversized Codex marketplaces stay on manual repair

Codex's `plugin marketplace upgrade` does not fetch into the existing snapshot — it re-clones the whole source repository into `~/.codex/.tmp/marketplaces/.staging/` under a hardcoded 30-second timeout, then swaps (confirmed on `codex-cli` 0.147.0). `thedotmack/claude-mem` is ~330MB with history and takes ~44s to full-clone, so its Codex marketplace can never refresh: acquire fails with `fatal: early EOF`, the native verification gate for the `claude-mem` dual-plugin skill stays blocked, and its duplicate surface copies survive cleanup. The failure is deterministic, not transient, and recurs with every claude-mem release. Smaller marketplaces (Waza 4.5MB, visual-explainer 4.2MB) finish inside the window.

We do not automate a marketplace repair. The recovery otherwise stays a manual, documented procedure: fast-forward the snapshot with `git -C ~/.codex/.tmp/marketplaces/<name> fetch origin main && git merge --ff-only origin/main` (~1s, purely additive), run `codex plugin add <plugin>@<name>`, then hand-sync the two bookkeeping fields Codex would have written — `revision` in `.codex-marketplace-install.json`, and `last_revision` / `last_updated` under `[marketplaces.<name>]` in `~/.codex/config.toml`.

The one exception is `agent-tooling/repair-claude-mem-marker.sh`. Codex marketplace installs of claude-mem can omit `.install-version`, causing `version-check.js` to emit a successful warning and skip SessionStart context injection. The operator runs this script explicitly; it repairs by default and `--check` previews drift. For each non-orphaned cache version, it reads the installed package version and writes only the matching marker. It never changes a marketplace snapshot, Codex metadata, `config.toml`, plugin registration, or dependency state. It never invokes `codex` or `npx`, and no routine updater calls it.

The only code change is diagnostic. `upgrade_codex_marketplace` retried three times, two seconds apart, against a failure that cannot succeed on retry, turning one real problem into three identical errors. It now recognises the clone-timeout signature, stops after the first attempt, and prints one error naming the cause and this ADR. Failures that could be transient keep the full retry budget.

## Considered options

Two broader automated fixes were designed and rejected. The first was **native-state repair**: the private adapter performs the fetch itself and hand-writes Codex's snapshot, install metadata, and `config.toml` fields. It works, but it makes this repo permanently liable for three undocumented Codex-internal formats that are free to change between releases, and it puts a private adapter — defined as reconciling one manifest source *without owning policy* — in charge of another CLI's bookkeeping. The marker-only script above is not this repair: it has one stable file format, derives its value from the installed package, and does not reconcile marketplace state.

The second was an **adapter-owned marketplace clone**: keep a shallow clone under `~/.cache/agent-scripts/marketplaces/<sourceId>` and register it with Codex as a `source_type = "local"` marketplace, which removes the full clone from the picture entirely. This was implemented and tested before being dropped. It is sound, and it keeps every write to Codex state going through `codex` commands, but it buys automation of a few minutes per release in exchange for a permanent second code path in the plugin adapter, a per-machine cache directory that git never carries, and a destructive one-time migration — `codex plugin marketplace remove` drops the installed plugin and its `hooks.state` trusted hashes. The cost of the failure did not justify the standing complexity.

A third option, re-registering the git marketplace with `--sparse`, stays fully native and a sparse probe finishes in ~2.5s, but it is unverified whether later `upgrade` runs honour recorded `sparse_paths`, and finding out costs the same destructive re-registration.

## Consequences

Each claude-mem release can remove the Codex runtime marker. The explicit marker repair restores the SessionStart precondition without attempting a marketplace update. A marketplace refresh failure remains a separate manual recovery problem.

Plugin-managed recovery is otherwise unchanged: reconciliation still never substitutes a surface copy for a failed plugin, and broad **native-state repair** remains named and rejected in the glossary.

The underlying Codex defect — a full clone under a hardcoded timeout with no configurable escape — should be reported upstream. An incremental fetch, a partial clone, or a timeout knob in Codex removes the problem at its source and is the outcome worth waiting for. If the manual repair becomes frequent enough to hurt, the adapter-owned local clone above is the fallback design, and it was proven workable.
