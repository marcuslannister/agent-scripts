---
status: accepted
---

# Oversized Codex marketplaces install from an adapter-owned local clone

Codex's `plugin marketplace upgrade` does not fetch into the existing snapshot — it re-clones the whole source repository into `~/.codex/.tmp/marketplaces/.staging/` under a hardcoded 30-second timeout, then swaps (confirmed on `codex-cli` 0.147.0). `thedotmack/claude-mem` is ~330MB with history and takes ~44s to full-clone, so its Codex marketplace can never refresh: every acquire run fails with `fatal: early EOF`, the native verification gate for the `claude-mem` dual-plugin skill stays blocked, and its duplicate surface copies survive cleanup. The failure is deterministic, not transient, and recurs with every claude-mem release; it has so far been cleared by hand. Smaller marketplaces (Waza 4.5MB, visual-explainer 4.2MB) finish inside the window.

Where a Codex git marketplace cannot complete its own fetch, the private adapter owns a shallow clone of the upstream repository under `~/.cache/agent-scripts/marketplaces/<sourceId>` and registers it with Codex as a `source_type = "local"` marketplace. Refreshing that marketplace becomes an incremental fetch of the adapter's own clone; discovery, installation, enable/disable state, and verification all stay on native `codex` commands. The strategy is opt-in per `registry.json` entry rather than a `claude-mem` branch, because any upstream can outgrow the window and a second special-case file would be one too many. `upgrade_codex_marketplace` stops retrying when the failure carries the deterministic clone-timeout signature; its three 2-second retries currently turn one real problem into three identical errors.

## Considered options

Repairing Codex's snapshot in place was the obvious fix and is rejected: fetch into `~/.codex/.tmp/marketplaces/<name>`, fast-forward, `codex plugin add`, then hand-write `revision` in `.codex-marketplace-install.json` and `last_revision`/`last_updated` under `[marketplaces.<name>]` in `config.toml`. It works — it is exactly how the 13.13.1 gate was cleared manually — but it makes this repo permanently liable for three undocumented Codex-internal formats that are free to change between Codex releases, and it puts a private adapter, defined as reconciling one manifest source *without owning policy*, in charge of another CLI's bookkeeping. Re-registering the git marketplace with `--sparse` was the most attractive alternative because it stays fully native and a sparse probe finishes in ~2.5s, but it is unverified whether later `upgrade` runs honour recorded `sparse_paths`, and finding out costs the same destructive re-registration as the option we chose. Doing nothing leaves a hand repair due at every claude-mem release.

## Consequences

Migration is a swap, not an edit. `codex plugin marketplace remove` drops the installed plugin along with its `hooks.state` trusted hashes, so the new local marketplace is registered and confirmed to list the plugin at the expected version *before* the old `claude-mem-local` registration is removed. The marketplace name derives from the local path, so `registry.json`'s `plugin.marketplaces.codex` value and the resulting plugin id both change away from `claude-mem@claude-mem-local`.

The clone lives in a tooling-owned cache rather than under `~/Projects`, deviating from `visual-explainer.sh`'s working-clone precedent: it is machine-local scratch that the adapter is free to re-create, not a checkout the operator manages. It is per-machine state that git never carries, so it is created and refreshed by the same plugin reconciliation that `update-local.sh` already runs (ADR-0005).

This does not weaken plugin-managed recovery. Reconciliation still never substitutes a surface copy for a failed plugin; the change is to where a native plugin installs *from*, and every write to Codex state still goes through `codex`. Direct writes into another CLI's internal storage are named and rejected in the glossary as **Native-state repair**.

The underlying Codex defect — a full clone under a hardcoded timeout with no configurable escape — should be reported upstream. If Codex gains an incremental fetch, a partial clone, or a configurable timeout, this mechanism can be deleted and the marketplace re-registered as a plain git source, which is what makes this decision reversible.
