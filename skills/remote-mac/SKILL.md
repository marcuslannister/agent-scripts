---
name: remote-mac
description: "Peter's Macs: MacBook, Mac Studio, clawmac, Tailscale, SSH, OpenClaw runtime topology."
---

# Remote Mac

Use when the user says `MacBook`, `Mac Studio`, `clawmac`, `moltymac`, `Molty`, Tailscale, or asks to run/check something on one of Peter's Macs.

## Peter's Topology

- Primary daily driver: Peter's MacBook Pro, local host `steipete-mbp`, Tailscale `peters-macbook-pro-1`.
- Workhorse: Mac Studio, Tailscale `peters-mac-studio-1`, usually best reached as `steipete@steipete-macstudio.local`.
- Personal cloud OpenClaw: `clawmac`, Tailscale/SSH `steipete@clawmac`, gateway via LaunchAgent `ai.openclaw.gateway`, loopback `127.0.0.1:18789`, Telegram connected.
- Molty: runs on Mac Studio, not `moltymac`, when healthy. Expected runtime is tmux session `openclaw-gateway-watch-main` from `/Users/steipete/clawdbot` with `pnpm gateway:watch --benchmark`, LAN bind `*:18789`, Discord bot `Molty`, plus Slack and Telegram connected.
- `moltymac`: old/alternate node. If Tailscale shows it offline or SSH times out, do not treat it as the live Molty runtime.

Manager repo source of truth:

- `/Users/steipete/Projects/manager/computers.yaml`
- `/Users/steipete/Projects/manager/agents.yaml`

## Discovery

1. Start with `tailscale status` and pick the matching host.
2. If Tailscale is down or SSH times out, try LAN discovery:

```bash
dns-sd -B _ssh._tcp local
arp -a
```

3. Try mDNS names such as `HOST.local` when visible.
4. For Mac Studio, prefer `steipete-macstudio.local` when Tailscale SSH times out.

## SSH Rules

Use non-interactive SSH by default:

```bash
ssh -o RequestTTY=no -o RemoteCommand=none HOST 'COMMAND'
```

The local SSH alias `mac-studio` auto-attaches tmux. For one-shot commands, either use `steipete@steipete-macstudio.local` or override both options above.

For long-running or interactive remote work, use tmux on the remote host and keep the session name obvious.

## OpenClaw Checks

Use login shells on remote Macs so Homebrew and pnpm are on PATH:

```bash
ssh -o RequestTTY=no -o RemoteCommand=none steipete@steipete-macstudio.local \
  'zsh -lc "openclaw gateway status --json; openclaw channels status --json"'
```

Mac Studio / Molty healthy shape:

- `tmux list-sessions` includes `openclaw-gateway-watch-main`.
- `ps axww` includes `pnpm gateway:watch --benchmark`.
- `lsof -nP -iTCP:18789 -sTCP:LISTEN` shows a listener on `*:18789`.
- `openclaw channels status --json` shows Discord `Molty`, Slack, and Telegram connected.

clawmac healthy shape:

- `launchctl list` includes `ai.openclaw.gateway`.
- `lsof -nP -iTCP:18789 -sTCP:LISTEN` shows loopback listeners.
- `openclaw channels status --json` shows Telegram connected.

## Safety

- Do not assume host identity from a stale IP; verify hostname/user when possible.
- Do not print secrets from remote files or shells.
- If a host is unavailable after Tailscale + LAN fallback, say what was tried.
- For OpenClaw Gateway on Peter's machines, follow repo docs/AGENTS; do not install/start/stop services unless asked.
