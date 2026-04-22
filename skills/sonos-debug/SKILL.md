---
name: sonos-debug
description: "Diagnose Peter's local Sonos reliability issues on UniFi: discovery, firmware skew, packet loss/latency, AP/radio/client placement, mesh uplinks, multicast/IGMP settings, and safe UniFi read-only audits. Use when asked about Sonos, UniFi Wi-Fi reliability, speakers dropping, grouping/discovery problems, or network tuning for Sonos."
metadata:
  short-description: Debug Sonos on UniFi
---

# Sonos Debug

Use for Peter's Sonos + UniFi reliability work.

## Rules

- `op` only inside tmux. Use `scripts/unifi-auth-tmux.sh`; never call `op` directly.
- Do not print secrets. Query selected fields; redact WLAN/passphrase data.
- Prefer read-only first. Ask before risky changes; Wi-Fi width/roaming tweaks are usually OK when requested.
- Clean `/tmp/unifi-*` cookies/files and tmux sessions when done unless continuing.

## Workflow

1. Sonos health:
   `scripts/sonos-snapshot.sh`
2. UniFi auth, if needed:
   `scripts/unifi-auth-tmux.sh 192.168.0.1`
3. UniFi Wi-Fi/Sonos snapshot:
   `scripts/unifi-sonos-snapshot.sh`
4. Compare with symptoms:
   - firmware skew: update Sonos app
   - packet loss/high latency: ping affected rooms again
   - poor client placement/rates: inspect Sonos rows
   - mesh AP: wire it if possible

## Local Heuristics

- Good baseline: 2.4 GHz `20 MHz`, 5 GHz `80 MHz`, DFS off for Sonos-heavy house.
- Best reliability win: wire wireless-mesh APs; Office AP was meshed around `-65 dBm`.
- Disable Fast Roaming / 802.11r on Sonos/IoT SSIDs; keep BSS Transition on.
- IGMP snooping should stay on for the LAN.
- If debugging discovery from the Mac, avoid Ethernet + Wi-Fi active on same LAN.
- Dedicated Sonos/IoT SSID option: WPA2, 2.4 GHz only, no fast roaming.
