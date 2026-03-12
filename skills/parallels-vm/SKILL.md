---
name: parallels-vm
description: Automate and verify Parallels Desktop macOS guests on Peter's Mac. Covers `prlctl` lifecycle/snapshots/screenshots, guest command execution, website installs, OpenClaw release smoke runs from `openclaw.ai`, update/status verification, SSH bootstrap, and optional Peekaboo GUI automation.
---

# Parallels Desktop

Use this skill for Parallels VM work on Peter's Mac.

Primary tools:

- `prlctl` for power, snapshots, guest exec, guest screenshots, VM info
- `peekaboo` for host-side GUI automation of the Parallels app/window
- `ssh` / Screen Sharing / RDP inside the guest for robust control

## Fast Path

1. Verify `prlctl` exists: `which prlctl`
2. List VMs: `prlctl list -a`
3. Inspect target VM: `prlctl list -i "<vm>"`
4. Prefer guest-native control first:
   - `prlctl exec "<vm>" --current-user ...`
   - `ssh user@<guest-ip>`
5. Use `peekaboo` only when GUI interaction is required.

Guest exec pitfalls:

- `prlctl exec "<vm>" ...` without `--current-user` often runs as `root`; this is wrong for per-user launchd checks on macOS guests
- `prlctl exec` can have a minimal PATH even with `--current-user`; Homebrew CLIs may fail with `command not found` or `env: node: No such file or directory`
- `prlctl exec` also mangles shell-heavy commands more often than it should on macOS guests; for pipes, redirects, heredocs, or interactive flows, prefer `prlctl enter "<vm>" --current-user --use-advanced-terminal`
- prefer absolute guest paths for Homebrew tools on macOS guests, for example `/opt/homebrew/bin/openclaw`, `/opt/homebrew/bin/node`, `/usr/bin/grep`, `/usr/bin/plutil`
- if you need shell features or user PATH, wrap with a real shell explicitly: `prlctl exec "$VM" --current-user zsh -lc '<cmd>'`
- if a guest-installed npm CLI fails under `prlctl exec` but works interactively, bypass the shebang and run the entrypoint with absolute Node, for example `/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/openclaw/openclaw.mjs ...`
- when validating a same-version npm reinstall inside the guest, use a cache-busted tarball filename and inspect the installed compiled file, not just `--version`; npm may leave the old hashed bundle in place if you keep reinstalling the same filename/version pair

Reusable helpers:

- `scripts/prl-macos-enter.sh <vm>`: open a real guest shell via `prlctl enter`
- `scripts/prl-macos-pnpm.sh <vm> <guest-repo-dir> <pnpm args...>`: run guest `pnpm` through absolute Homebrew Node + PATH
- `scripts/prl-macos-download.sh <vm> <url> <guest-path>`: download a URL to a guest file first; safer than `curl | bash` through `prlctl exec`
- `scripts/prl-macos-openclaw.sh <vm> [--env KEY=VALUE ...] <openclaw-args...>`: run guest OpenClaw via absolute Node + resolved entrypoint
- `scripts/prl-macos-install-openclaw.sh <vm> [--version latest]`: run the website installer reliably inside the guest
- `scripts/prl-macos-gateway-status-version.sh <vm> [--profile <name>] [--state-dir <dir>] [--json]`: fetch gateway status and extract `runtimeVersion`, `rpc.ok`, pid, and port data
- `scripts/prl-macos-openclaw-update-verify.sh <vm>`: end-to-end published release smoke; install old version from `openclaw.ai`, verify gateway, update to latest, re-verify, and auto-fallback to manual gateway launch when Tahoe launchd bootstrap is broken
- `scripts/prl-macos-auth-seed.sh <vm> <local-auth-profiles.json|->`: seed `auth-profiles.json` into the guest with base64 transport

## Purpose-Built Wrappers

When the task is about OpenClaw install/update verification on a macOS guest, prefer the wrappers over ad-hoc `prlctl exec`:

- `prl-macos-install-openclaw.sh`: downloads `install.sh` to the guest first, then runs it with explicit PATH/env
- `prl-macos-openclaw.sh`: bypasses shebang/PATH issues by calling guest OpenClaw with absolute Node + `dist/entry.js`
- `prl-macos-gateway-status-version.sh`: normalizes noisy `gateway status --json` output into a compact version/probe summary
- `prl-macos-openclaw-update-verify.sh`: does the Tahoe-style "install old -> verify gateway -> update -> verify gateway" flow and falls back to a detached manual `gateway run` probe after forcing `gateway.mode=local` if LaunchAgent bootstrap fails
- `prl-macos-auth-seed.sh`: avoids fragile inline JSON writes when a live test needs stored auth profiles

## Core Commands

```bash
VM="macOS Tahoe"

prlctl start "$VM"
prlctl status "$VM"
prlctl list -i "$VM"
prlctl exec "$VM" --current-user whoami
prlctl capture "$VM" --file /tmp/parallels-shot.png

prlctl snapshot "$VM" --name pre-change
prlctl snapshot-list "$VM" --tree
prlctl snapshot-switch "$VM" --id <snapshot-id>
prlctl snapshot-delete "$VM" --id <snapshot-id>
```

Helper examples:

```bash
VM="macOS Tahoe"
REPO="/Users/steipete/Projects/openclaw-parallels-gpt54"

scripts/prl-macos-pnpm.sh "$VM" "$REPO" install
scripts/prl-macos-pnpm.sh "$VM" "$REPO" build
scripts/prl-macos-pnpm.sh "$VM" "$REPO" check
scripts/prl-macos-pnpm.sh "$VM" "$REPO" test
scripts/prl-macos-install-openclaw.sh "$VM" --version 2026.3.7
scripts/prl-macos-gateway-status-version.sh "$VM" --json
scripts/prl-macos-openclaw-update-verify.sh "$VM" --from-version 2026.3.7 --to-tag latest
```

Useful IP extractor:

```bash
vmip() { prlctl list -i "$1" | awk -F': ' '/IP Addresses/{print $2}'; }
```

## SSH Bootstrap

Shared networking is usually enough for host-to-guest SSH. Check guest IP from `prlctl list -i`.

Probe SSH:

```bash
nc -G 2 -vz "$(vmip "$VM")" 22
```

If closed on a macOS guest, enable Remote Login in the guest:

- UI: `System Settings > General > Sharing > Remote Login`
- CLI in guest when creds allow: `sudo systemsetup -setremotelogin on`

Then:

```bash
ssh "$USER@$(vmip "$VM")"
```

If the user wants stable local forwarding like `localhost:2222`, configure a Parallels NAT port-forward rule instead of relying on changing guest IPs.

## macOS Guest Debugging

For launchd-managed services on a macOS guest, use the guest console user, not root:

```bash
VM="macOS Tahoe"
prlctl exec "$VM" --current-user 'whoami && echo HOME=$HOME && id -u'
```

Gateway / launchd checks that worked well:

```bash
VM="macOS Tahoe"
prlctl exec "$VM" --current-user 'label=ai.openclaw.gateway; domain=gui/$(id -u); plist=$HOME/Library/LaunchAgents/$label.plist; ls -l "$plist"; launchctl print "$domain/$label"'
prlctl exec "$VM" --current-user 'launchctl print-disabled gui/$(id -u) | /usr/bin/grep -E "ai\\.openclaw|openclaw" || true'
prlctl exec "$VM" --current-user 'lsof -nP -iTCP:18789 -sTCP:LISTEN || true'
prlctl exec "$VM" --current-user 'curl -i --max-time 5 http://127.0.0.1:18789/health || true'
```

Notes:

- `launchctl print gui/$(id -u)/<label>` is the fastest way to prove “plist exists but launchd lost the service”
- `curl http://127.0.0.1:<port>/health` and `lsof -iTCP:<port>` are more reliable than app-specific CLIs when PATH/env inside `prlctl exec` is broken
- if a service CLI fails under `prlctl exec`, first verify whether the binary or its shebang target is missing from PATH before assuming the service is down

OpenClaw/Tahoe notes:

- Fresh macOS guests may have Homebrew `node` but no `pnpm`; install once with `/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/npm/bin/npm-cli.js install -g pnpm`
- `prlctl exec` is fine for argv-style commands; for pipes, heredocs, JSON blobs, or multiline shell work, switch to `scripts/prl-macos-enter.sh`
- Website installer verification should use `scripts/prl-macos-install-openclaw.sh`, not raw `curl | bash` through `prlctl exec`
- Gateway version verification should use `scripts/prl-macos-gateway-status-version.sh`; it strips pre-JSON warnings and reports `runtimeVersion` when present
- Real release smoke should prefer `scripts/prl-macos-openclaw-update-verify.sh`; it now tolerates Tahoe `launchctl bootstrap ... Input/output error` by falling back to a detached manual gateway probe
- Released builds may still print `/dev/tty: Device not configured` during noninteractive installer tail work (`doctor` / plugin updates); treat that as a follow-up bug unless the requested version failed to land
- If manual gateway probing is needed, first force `gateway.mode=local`; released builds can otherwise block startup with `set gateway.mode=local (current: unset) or pass --allow-unconfigured`
- For listener checks, use `lsof -nP -iTCP:<port> -sTCP:LISTEN`; plain `lsof -i :<port>` is too noisy on Tahoe
- `src/gateway/gateway-models.profiles.live.test.ts` currently filters on stored auth profiles; env-only `OPENAI_API_KEY` is not enough there, so use `scripts/prl-macos-enter.sh` and write/copy `~/.openclaw/agents/main/agent/auth-profiles.json` inside the guest before rerunning

## GUI Automation

Use `prlctl capture` for the guest screenshot itself.

Use Peekaboo for host-side automation of the Parallels window:

```bash
peekaboo see --app Parallels --json
peekaboo click --app Parallels --coords 500,400
peekaboo type --app Parallels "hello"
```

Important:

- `prlctl capture` pixels are guest-native
- `peekaboo click/type` target the visible host window
- coordinate mapping gets fragile if the Parallels window is scaled, moved, fullscreened, or retina-scaled differently

Best practice:

- keep the VM window visible and stable if using Peekaboo
- prefer SSH / Screen Sharing / RDP for serious automation
- use `prlctl send-key-event` only for limited key injection

## Snapshot Safety

- Take a snapshot before risky changes.
- Do not delete or switch snapshots unless asked or clearly part of the requested workflow.
- Call out that snapshot revert discards later guest state.

## Decision Rule

- Need lifecycle / state / metadata / screenshots: use `prlctl`
- Need commands inside guest: use `prlctl exec` or `ssh`
- Need desktop UI control: use guest-native remote control first, Peekaboo second
- Need reproducible visual automation from the host: combine `prlctl capture` for read + Peekaboo for action, but warn about coordinate drift

## Peter Notes

- `peekaboo` is on PATH on this Mac.
- `~/.codex/skills` points to `~/Projects/agent-scripts/skills`, so edits there are live for Codex.
