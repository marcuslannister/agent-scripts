---
name: browser-use
description: "Chrome DevTools MCP automation for the existing Chrome tabs; no AppleScript."
---

# Browser Use

Use this for browser tasks against the existing Chrome session.

Config repair details live in `mcporter-config.md`.

Hard rule: reattach to the existing Chrome profile only. Use this target:

```bash
mcporter call chrome-devtools.<tool>
```

Never use `chrome-isolated`, Playwright, Puppeteer, the Codex in-app browser, AppleScript, `osascript`, GUI scripting, or macOS `open` for browser control unless the user explicitly asks for an isolated/new browser.

## Check MCP

```bash
mcporter list chrome-devtools --schema
mcporter call chrome-devtools.list_pages --args '{}' --output text
```

`list_pages` must show the user's real open tabs. If it shows a blank/default isolated Chrome, stop and say reattach failed.

If the call appears to hang while Chrome shows an auth/attach/update prompt, wait for approval. Prefer Peekaboo to press an explicit Chrome `Allow` button when visible; otherwise wait for the human. Do not restart daemons or kill MCP processes just because the first output is slow.

If `list_pages` fails with `DevToolsActivePort`, ask the user to restart Chrome or the DevTools bridge, then retry once:

```bash
mcporter daemon restart
mcporter call chrome-devtools.list_pages --args '{}' --output text
```

If it still fails, stop and say Chrome DevTools MCP is unavailable. Do not use AppleScript.

Avoid noisy recovery loops. Repeated MCP/browser restarts can trigger
reconnect/login prompts and alerts. Try once, then pause and choose a quieter
path.

## Typical Flow

```bash
# pick the page id from list_pages
mcporter call chrome-devtools.select_page --args '{"pageId":9}' --output text

# inspect page
mcporter call chrome-devtools.take_snapshot --args '{}' --output text

# navigate selected page
mcporter call chrome-devtools.navigate_page --args '{"url":"https://example.com"}' --output text

# click an element uid from the latest snapshot
mcporter call chrome-devtools.click --args '{"uid":"1_38","includeSnapshot":true}' --output text

# type/fill
mcporter call chrome-devtools.fill --args '{"uid":"1_13","value":"text","includeSnapshot":true}' --output text

# run JS, keep secrets out of output
mcporter call chrome-devtools.evaluate_script --args '{"function":"() => document.title"}' --output json
```

Use `take_snapshot` before actions and use current `uid` values only. Avoid `take_screenshot` unless visual layout matters.

## Secret Handling

Never print tokens/passwords from page DOM, network logs, or inputs. For token checks, return shape only: present/absent, length, status code, account/org name.
