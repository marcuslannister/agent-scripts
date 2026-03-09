---
name: parallels-vm
description: Automate and inspect Parallels Desktop VMs on Peter's Mac. Use when working with `prlctl`, VM lifecycle, snapshots, guest screenshots, guest command execution, SSH bootstrap, or host-side GUI control via Peekaboo against the Parallels window.
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
- prefer absolute guest paths for Homebrew tools on macOS guests, for example `/opt/homebrew/bin/openclaw`, `/opt/homebrew/bin/node`, `/usr/bin/grep`, `/usr/bin/plutil`
- if you need shell features or user PATH, wrap with a real shell explicitly: `prlctl exec "$VM" --current-user zsh -lc '<cmd>'`

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
