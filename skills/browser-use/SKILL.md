---
name: browser-use
description: "Control the user's existing signed-in Chrome: callable Codex Chrome plugin first, then OpenClaw extension-backed mcporter, with direct DevTools attachment only as a last fallback."
---

# Browser Use

Control the user's existing real Chrome profile, especially for login-dependent work and live UI verification.

## Route

1. Use the Codex `Chrome` or `Chrome [Internal]` plugin when it is callable in
   the active session. Installed on disk is not enough.
2. Otherwise prefer the OpenClaw extension-backed mcporter route.
3. Use legacy direct DevTools attachment only as the explicit last fallback.

For mcporter, use only the normal interface:

```bash
mcporter call chrome-devtools.<tool>
```

Never use isolated Chrome, the Codex in-app browser, Playwright, Puppeteer,
AppleScript, `osascript`, generic GUI scripting, or macOS `open` as a browser-control
substitute unless the user explicitly asks for an isolated or new browser.
Peekaboo is allowed only for Chrome or extension setup and visible prompts.
Login-heavy sites often depend on the real profile's cookies, SSO, device trust,
and extensions.

For a rendered-browser bug, prove behavior through this real profile. Treat
`curl`, source inspection, API checks, and isolated test browsers as supporting
evidence, not substitutes for live UI proof.

## Extension Relay Model

OpenClaw creates a random per-host relay secret in its mode-`0600`
`credentials/` directory. Pairing gives the Chrome extension a relay URL plus
that secret. The extension stores both in `chrome.storage.local` and
authenticates its WebSocket through WebSocket subprotocols; the secret is not
placed in the request URL.

On a same-host relay, mcporter reads the local secret, probes `/json/version`
with Bearer authentication, then connects `chrome-devtools-mcp` to the
authenticated `/cdp` endpoint. Keep credentials out of configuration, command
output, chat, logs, and screenshots.

The relay exposes only tabs in the Chrome tab group titled **OpenClaw**. Group
membership is the user-visible consent and authorization boundary: putting a
tab in shares it; removing the tab revokes access. Group color is irrelevant.

### Topology Boundary

Direct remote Gateway pairing over `wss://` lets OpenClaw's Gateway-side
browser tool control local Chrome. It does not create a local relay for a local
mcporter process. Do not routinely copy remote secrets or build ad-hoc SSH
tunnels around this boundary.

If local mcporter cannot authenticate to a local relay, the extension-backed
mcporter route is unavailable. Report that clearly or use the labeled legacy
fallback; never represent remote Gateway control or direct attachment as local
relay success.

## Setup and Repair

- Resolve the unpacked extension with `openclaw browser extension path`, then
  verify `<path>/manifest.json` before loading or presenting it. The source
  fallback is `~/Projects/openclaw/extensions/browser/chrome-extension`; verify
  its manifest too.
- Pair through the extension popup without printing the pairing string in chat
  or captured tool output, and never put it in shell history, logs, or screenshots.
  Paste it only into the confirmed popup and clear any temporary clipboard value.
- Confirm the popup reports **Connected · N tabs shared** and that the intended
  tab is in the **OpenClaw** group.
- Restart the mcporter daemon after pairing or changing the relay route, then
  re-run readiness proof from scratch.
- Remote pairing with `--gateway-url` serves the Gateway browser path; it does
  not make the relay available to local mcporter.

Do not use `openclaw browser extension cdp --json` or inspect process arguments
as routine diagnostics: both can expose relay credentials. If credential
exposure is suspected, rotate the per-host secret and pair again.

## Fail-Closed Readiness Proof

Require every condition below before calling the extension route ready:

1. The popup says **Connected · N tabs shared**.
2. The intended disposable tab is shared and belongs to the **OpenClaw** group.
3. mcporter has been restarted after pairing or relay-route changes.
4. `list_pages` matches the shared tab set exactly. If unrelated, unshared tabs
   appear, mcporter used full-profile legacy attachment; do not count that as
   extension success.
5. Navigation and evaluation both succeed in the disposable shared tab.

```bash
mcporter call chrome-devtools.list_pages --args '{}' --output text
mcporter call chrome-devtools.select_page --args '{"pageId":9}' --output text
mcporter call chrome-devtools.navigate_page --args '{"url":"https://example.com/?openclaw-relay-proof=1"}' --output text
mcporter call chrome-devtools.evaluate_script --args '{"function":"() => ({title: document.title, href: location.href})"}' --output json
```

A blocking **Allow remote debugging?** prompt proves legacy attachment was
attempted. Its absence alone does not prove the relay path; the popup, group,
exact page set, and read/write checks provide that proof.

## Typical Flow

List pages, select only a shared target, snapshot before acting, and use fresh
snapshot UIDs. Prefer DOM snapshots over screenshots unless layout matters.

```bash
mcporter call chrome-devtools.list_pages --args '{}' --output text
mcporter call chrome-devtools.select_page --args '{"pageId":9}' --output text
mcporter call chrome-devtools.take_snapshot --args '{}' --output text
mcporter call chrome-devtools.click --args '{"uid":"1_38","includeSnapshot":true}' --output text
mcporter call chrome-devtools.fill --args '{"uid":"1_13","value":"text","includeSnapshot":true}' --output text
mcporter call chrome-devtools.evaluate_script --args '{"function":"() => document.title"}' --output json
```

For live UI proof, capture the current page state before the action, perform
the requested interaction, then snapshot or evaluate the rendered result.
Keep secrets out of DOM, input, network, console, and screenshot output. For
credential checks, return only safe shape such as present/absent, length,
status code, or account/organization label.

If automation is unavailable, report the verification gap instead of silently switching to prohibited or isolated tooling.

## Legacy Fallback: Full-Profile Direct Attachment

Use this only after the callable plugin and authenticated local extension relay
are unavailable. It exposes the full real-profile tab set and can show Chrome's
blocking **Allow remote debugging?** prompt.

When a visible, unambiguous Chrome prompt asks to allow the attachment, approve
it once, then rerun `list_pages`. If the prompt is absent, ambiguous, or the
retry fails, stop and ask the user or report that Chrome DevTools MCP is
unavailable. Do not loop approvals, repeatedly restart Chrome or mcporter, or
kill browser processes.

Verify that `list_pages` shows the intended real-profile tabs before acting. Always
label this path as full-profile direct attachment, never as OpenClaw extension relay success.
