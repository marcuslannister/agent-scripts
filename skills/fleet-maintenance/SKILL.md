---
name: fleet-maintenance
description: "Mac fleet upkeep: global packages, safe repo sync, Xcode, disk, Trash, and health."
---

# Fleet Maintenance

Maintain Peter's Macs without disturbing active coding agents or ambiguous local work. Use `$remote-mac` for inventory/SSH and `$xcode-sync` for all Xcode work.

## Safety contract

- Read `~/Projects/manager/computers.yaml`; use live Tailscale state and deduplicate hosts by hardware UUID. Exclude handed-off and unknown machines.
- Audit hosts in parallel; mutate one host at a time. Recheck agent activity immediately before every package, repo, or Xcode mutation.
- Treat any user process whose cwd is inside a repo, Git lock, dirty worktree, or file modification within three days as active. Skip it.
- Never reset, clean, stash, rebase, switch branches, delete local work, push, install macOS updates, or reboot during routine maintenance.
- Snapshot role-critical services before package updates. Do not restart OpenClaw gateways or other services unless explicitly authorized; verify them afterward using their owning skill.
- Keep a per-host action log. An unreachable host is pending, never current.

## Run order

1. Inventory and preflight.
2. Sync eligible repos using the existing Git/toolchain.
3. Update Homebrew and global npm packages on inactive hosts.
4. Verify each host's macOS stable/beta track.
5. Sync Xcode through `$xcode-sync`.
6. Empty Trash only when explicitly requested for this run; perform approved package cleanup.
7. Re-audit disk, tools, repos, and role-critical services.

## Preflight

Record hostname, hardware UUID, macOS, architecture, uptime, Tailscale state, selected Xcode, free bytes/percent, Trash size, Homebrew prefix/version, Node/npm versions, running Brew services, and active coding-agent processes.

Classify startup-disk space using both absolute and relative capacity:

- healthy: at least 100 GiB and 15% free
- warning: 50–100 GiB or 10–15% free
- critical: below 50 GiB or 10% free

Do not start Xcode expansion on warning/critical space. Never delete outside Trash, superseded package-manager artifacts, or Xcode paths governed by `$xcode-sync` without explicit approval.

## Repository sync

Run the read-only candidate audit on each host:

```bash
skills/fleet-maintenance/scripts/repo-sync-audit.sh ~/Projects 3
ssh -o RequestTTY=no -o RemoteCommand=none HOST 'bash -s -- "$HOME/Projects" 3' \
  < skills/fleet-maintenance/scripts/repo-sync-audit.sh
```

Only process rows marked `candidate`. Recheck the row immediately before mutation, then:

```bash
git -C "$repo" fetch --prune
git -C "$repo" rev-list --left-right --count HEAD...@{upstream}
```

Interpret counts as `ahead behind`:

- `0 0`: current; no action.
- `0 N`: inspect `git log --oneline HEAD..@{upstream}` and `git diff --stat HEAD..@{upstream}`. If this is the configured upstream and the worktree remains clean/inactive, run `git pull --ff-only`, then verify clean/current.
- `N 0` or `N M`: inspect local commit subjects/authors and `git diff --stat @{upstream}...HEAD`; explain likely intent and escalate. Never push or rewrite.
- detached/no upstream/fetch failure: understand remotes, branches, recent commits, and worktree state; escalate with the smallest useful decision.

Do not infer that a stale local checkout should match a sibling checkout. Each visible checkout is user-managed.

## Homebrew

Skip mutation if Homebrew is absent or the host/role is active. Otherwise:

```bash
brew update
brew outdated --json=v2
brew services list
brew doctor
```

Classify every outdated formula/cask against running processes, Brew services, role-critical daemons, and active GUI apps. Build explicit safe lists; only when nonempty run `brew upgrade "${safe_formulae[@]}"` and `brew upgrade --cask "${safe_casks[@]}"`. Never use bare `brew upgrade` in fleet mode.

Treat `brew doctor` as advisory; do not blindly apply its suggestions. Compare services before/after. Use `brew cleanup --prune=30` after successful verification; use more aggressive cleanup only for disk pressure and explicit approval.

If an upgrade replaces Node, Git, Codex, or another executable used by an active agent/service, defer that formula rather than disrupting the process. Defer running casks. Do not change taps or uninstall packages automatically.

## Global npm packages

“Update npm” means registry-backed, top-level global packages—not project dependencies. Never change a repository's `package.json` or lockfile here.

1. Record `node --version`, `npm --version`, `npm prefix -g`, and `npm ls -g --depth=0 --json`.
2. Run `npm outdated -g --depth=0 --json`; its nonzero exit can mean updates exist.
3. Update each registry package to `name@latest`. Skip linked, file, Git, bundled, and ambiguous packages; report them.
4. Let the owner update npm itself: Homebrew updates a Homebrew Node/npm; only use `npm install -g npm@latest` for a self-managed npm installation.
5. Re-run inventory and smoke-test the updated global CLIs. Use `$npm` and `$one-password` only if a private package actually requires registry authentication; never expose npm credentials.

Major global-package updates are intended, but defer a package currently backing an active coding agent or service.

## macOS track

Record `sw_vers` product/build and current beta-seed enrollment. Resolve the latest stable and current beta build from authoritative current Apple sources; do not hardcode versions or infer track from version number alone. Use `softwareupdate --list` to confirm what the host is actually offered on its configured track.

Classify each Mac as current, update available, track ambiguous, unsupported, or unreachable. Preserve its configured stable/beta track. Routine maintenance does not switch tracks, install macOS updates, or reboot: prepare the exact update and request a maintenance window after confirming no active agents/services and adequate backup/disk state.

## Xcode

Invoke `$xcode-sync`; do not duplicate its install logic. Resolve current stable/beta/RC versions from an authoritative current source, not hardcoded versions. Preserve each host's selected stable or prerelease track while maintaining the canonical stable/prerelease slots and previous-major retention policy defined there.

Verify product build, signature, first-launch state, selection, host compatibility, and free space. Report unsupported and unreachable Macs separately.

## Trash and disk

Measure Trash on every run. Keep it read-only unless the current request explicitly says to clear/empty Trash. With that consent, empty only the current user's home-volume Trash after resolving and verifying the path:

```bash
trash="$HOME/.Trash"
home_real=$(cd "$HOME" && pwd -P)
trash_real=$(cd "$trash" && pwd -P)
if [[ "$trash_real" != "$home_real/.Trash" ]]; then
  printf 'refusing unexpected Trash path: %s\n' "$trash_real" >&2
  exit 2
fi
find "$trash_real" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
```

Never empty another user's Trash or Trash on external volumes. Recheck disk capacity afterward; escalate unexplained growth instead of broad cache deletion.

## Baseline health checks

Include these read-only checks in the report; mutations need separate authority:

- available macOS/security updates and whether a reboot is recommended
- Mac App Store application drift via `mas outdated`, when `mas` is installed
- last successful Time Machine backup, when configured
- SMART/storage warnings and APFS volume health signals available from `diskutil`
- uptime, clock synchronization, and laptop battery health/cycle count
- Tailscale reachability/version drift
- failed Brew services and role-specific LaunchAgents/daemons
- FileVault, firewall, Gatekeeper, and SIP status drift
- Developer ID certificate and important SSH credential expiry dates, never secret values

Useful optional maintenance: stale package caches/logs, abandoned containers/VMs, old simulators/device support, orphaned launch agents, and large Downloads. Audit first; delete only with explicit scope.

## Finish

Return a host matrix with: reachability, active/deferred reason, disk before/after, Trash reclaimed, Brew/npm changes, repos pulled/current/skipped/escalated, Xcode stable/prerelease build and selected track, backup/update/service warnings, and remaining user decisions.
