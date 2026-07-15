---
summary: 'Troubleshoot OneCLI requests made through Anvil Emacs when the daemon lacks HTTPS_PROXY.'
read_when:
  - A request works from the shell but returns 401 when run through Anvil Emacs.
  - Reconnecting an app does not fix an authenticated request made through Anvil Emacs.
---

# OneCLI requests from Anvil Emacs

## Problem

OneCLI injects credentials only when an HTTP client uses the gateway proxy from `HTTPS_PROXY`. A long-running Anvil Emacs daemon inherits its environment when it starts. If the daemon started outside `onecli run`, or before the gateway environment existed, it may not have `HTTPS_PROXY`.

A `curl` command started with `call-process` inside that daemon inherits the daemon environment. It can bypass OneCLI even when a shell in the same agent session has the gateway configured.

The common symptom:

1. An Anvil Emacs tool starts `curl`.
2. The service returns `401 Requires authentication`.
3. The response has no OneCLI `connect_url`.
4. Reconnecting the service changes nothing because the request never reached the gateway.

## Diagnosis

Check whether each execution context has the OneCLI proxy marker. Report only booleans. Never print the proxy value.

Inside Anvil Emacs:

```elisp
(let ((proxy (getenv "HTTPS_PROXY")))
  (list :https-proxy-present (and proxy (> (length proxy) 0))
        :onecli-marker (and proxy (string-match-p "aoc_" proxy))))
```

In the shell:

```zsh
if [[ -n "${HTTPS_PROXY:-}" && "$HTTPS_PROXY" == *aoc_* ]]; then
  print active
else
  print inactive
fi
```

If Emacs reports no proxy and the shell reports `active`, the two processes have different environments. A 401 from Emacs does not prove that the service is disconnected from OneCLI.

## Resolution

Run authenticated external requests with direct shell `curl` from the gateway-enabled shell:

```zsh
env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN \
  curl -sS --fail-with-body https://api.github.com/user
```

Do not add an authorization header. OneCLI injects credentials at the proxy boundary.

Keep using Anvil Emacs for local file reads, edits, and Emacs operations. Treat a network process launched inside the daemon as a separate execution context.

If a workflow requires network calls from Anvil Emacs, restart the Anvil Emacs daemon from a gateway-enabled environment. Re-run the boolean checks before sending the request.

## Safety rules

- Never print, copy, or manually export the proxy URL.
- Never ask for API keys or tokens as a workaround.
- Never infer OneCLI connection state from a request that bypassed the gateway.
- Check the execution context before asking the user to reconnect a service.
