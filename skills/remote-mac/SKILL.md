---
name: remote-mac
description: "Remote Macs: MacBook, Mac Studio, clawmac, Tailscale, SSH, OpenClaw."
---

# Remote Mac

Use when the user says `MacBook`, `Mac Studio`, `clawmac`, `moltymac`, `Molty`, Tailscale, or asks to run/check something on one of Peter's Macs.

## Peter's Topology

- Primary daily driver: Peter's MacBook Pro, local host `steipete-mbp`, Tailscale `peters-macbook-pro-1`.
- Workhorse: Mac Studio, Tailscale `peters-mac-studio-1`, usually best reached as `steipete@steipete-macstudio.local`.
- Personal cloud OpenClaw: `clawmac` (Peter may typo/say `crabmac`), Tailscale/SSH `steipete@clawmac`, gateway via LaunchAgent `ai.openclaw.gateway`, loopback `127.0.0.1:18789`, Telegram connected.
- Corporate-network boundary: `clawmac` and the personal LAN are unreachable from Peter's corporate-network Mac. Never use `clawmac` as a relay or LAN vantage from there.
- Molty: runs on Mac Studio, not `moltymac`, when healthy. Expected runtime is tmux session `openclaw-gateway-watch-main` from `/Users/steipete/clawdbot` with `pnpm gateway:watch --benchmark`, LAN bind `*:18789`, Discord bot `Molty`, plus Slack and Telegram connected.
- `moltymac`: old/alternate node. If Tailscale shows it offline or SSH times out, do not treat it as the live Molty runtime.

Manager repo source of truth:

- `/Users/steipete/Projects/manager/computers.yaml`
- `/Users/steipete/Projects/manager/agents.yaml`

## Discovery

1. Start with live `tailscale status --json`; match hostname/DNS name and use the node's current IP. Manager-cached Tailscale IPs may be stale.
2. On the corporate network, reach Mac Studio only through its live Tailscale node. MagicDNS may be disabled; use the current `TailscaleIPs[0]` directly. Do not try `clawmac`, mDNS, or personal-LAN discovery.
3. Outside the corporate network, if Tailscale is down or SSH times out, try LAN discovery:

```bash
dns-sd -B _ssh._tcp local
arp -a
```

4. Try mDNS names such as `HOST.local` only when on the same LAN.
5. If Mac Studio's live Tailscale node is offline from the corporate network, stop: it must wake or reconnect before SSH or Screen Sharing diagnosis can continue.

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

## clawmac GUI Access

- Prefer direct clawmac automation over Tailscale/SSH first: `open -a "Google Chrome"`, AppleScript, Chrome DOM JavaScript, and remote Peekaboo clicks.
- For `gog` OAuth on clawmac, keep the browser on clawmac. Start `gog auth add` in remote tmux, open the printed URL on clawmac Chrome, click consent with AppleScript/DOM automation, then verify with `zsh -lc 'gog auth list --check --json --no-input'`.
- If `GOG_KEYRING_PASSWORD` is exported by the remote shell environment, use the matching login shell for checks and tmux prompt feeding, and never print the value.
- If SSH/cron hits GUI-only prompts that direct automation cannot handle, use local Peekaboo through Jump Desktop's `clawmac` window as fallback.
- Find it with `peekaboo list windows --app "Jump Desktop" --json`; capture by `--window-title clawmac` or the reported `--window-id`.
- Clicks use local global coordinates through the Jump Desktop window; verify with a raw window screenshot before clicking.
- Chrome cookie/keychain issues: `security` may prompt for `Chrome Safe Storage`; Peter must enter the login keychain password, then click `Always Allow`.
- After approval, verify over SSH with `/Users/steipete/Projects/bird/bird check` and `/Users/steipete/.openclaw/bin/bird-gui check`.

## Safety

- Do not assume host identity from a stale IP; verify hostname/user when possible.
- Do not print secrets from remote files or shells.
- If a host is unavailable after Tailscale + LAN fallback, say what was tried.
- For OpenClaw Gateway on Peter's machines, follow repo docs/AGENTS; do not install/start/stop services unless asked.
