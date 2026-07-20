---
name: codex-huge-context
description: "Codex 1M context: direct OpenAI Responses API inference, static Sol/Terra/Luna catalogue, Keychain delivery, and safe Mac fleet rollout."
---

# Codex Huge Context

Use this skill when configuring, repairing, or auditing Codex's one-million-token context setup. The intended topology is a direct API inference route that preserves the normal ChatGPT login for Gmail, Calendar, and other connector OAuth:

```text
Codex inference -> Keychain auth helper -> https://api.openai.com/v1/responses
Codex connectors -> normal ChatGPT login in auth.json
```

This is not an HTTP proxy. The API remains authoritative for access, actual model limits, and billing.

## Target window

The static catalogue declares a 1,050,000-token raw context window for all three models:

- `gpt-5.6-sol`
- `gpt-5.6-terra`
- `gpt-5.6-luna`

Codex holds a 5% reserve, so the usable window is about 997,500 tokens. The catalogue only changes Codex's client-side clamp; it cannot make an unsupported API model accept a larger request.

## Required files

`~/.codex/models-api-1m.json` must contain `context_window` and `max_context_window` set to `1050000` for those three model slugs. Preserve the rest of the model metadata.

The root section of `~/.codex/config.toml` needs:

```toml
model = "gpt-5.6-sol"
model_provider = "openai_api_direct"
model_context_window = 1050000
model_catalog_json = "/Users/steipete/.codex/models-api-1m.json"

[model_providers.openai_api_direct]
name = "OpenAI API direct"
base_url = "https://api.openai.com/v1"
wire_api = "responses"
requires_openai_auth = false

[model_providers.openai_api_direct.auth]
command = "/Users/steipete/.codex/bin/fetch-openai-inference-key.zsh"
timeout_ms = 5000
refresh_interval_ms = 300000
```

Remove a legacy `model_auto_compact_token_limit` such as `233000`; otherwise Codex will compact at the old 272K-era threshold even though the catalogue permits 1M.

Before modifying a host, back up its config to a date-stamped sibling file. Do not replace unrelated project, plugin, MCP, notification, or approval settings.

## API credential delivery

The auth command reads a dedicated Keychain delivery copy, never a value in TOML or an environment variable:

```zsh
#!/bin/zsh
set -euo pipefail
exec /usr/bin/security find-generic-password \
  -a Codex \
  -s "Codex OpenAI inference API" \
  -w
```

Use `$one-password` before handling the API key. The canonical value is the `OPENAI_API_KEY` field in Molty's `AI API Key - OpenAI - OPENAI_API_KEY - Serviceable Access` item. Read it through the service-account workflow inside the shared `op-work` tmux session and store/update only the Keychain copy. Never print, copy over SSH, place in a profile, or write it to a temporary file.

The Keychain item should allow `/usr/bin/security`. A Keychain read normally produces no prompt. A login Keychain locked after reboot, or a command launched via noninteractive SSH, can fail with error 36 (`User interaction is not allowed`). Do not work around that failure with a plaintext file or a long-lived secret daemon: unlock the host from its local graphical session, install the item there, then use Codex from that local session.

Before the first fresh or resumed Codex launch on a configured machine, run the secret-safe preflight. It validates the direct-provider config, all three catalogue entries, helper executable, and non-empty helper delivery without printing the credential or helper stderr:

```zsh
ruby ~/.codex/skills/agent-scripts/codex-huge-context/scripts/preflight.rb
```

Do not mark a rollout complete or launch Codex when this fails. With `requires_openai_auth = false`, a missing Keychain delivery copy cannot fall back to the normal Codex login: the direct provider can reach `api.openai.com/v1/responses` without a bearer header and surface an opaque HTTP 401 instead. The preflight fails earlier with the bootstrap action needed. An unset `GITHUB_PAT_TOKEN` warning is independent and non-blocking for inference; it explains a concurrent GitHub MCP startup failure but must not be confused with OpenAI API authentication.

## ChatGPT connector login

`requires_openai_auth = false` applies only to the custom inference provider. The root Codex login must remain ChatGPT-authenticated for ChatGPT-connected plugins to work:

```zsh
codex login status
```

If it reports API-key login and the host needs Gmail, Calendar, or similar connectors, use `codex logout` followed by `codex login` from the local user session. Do not copy `auth.json` or OAuth tokens between Macs.

## Fresh and resumed sessions

`-m gpt-5.6-sol` selects a model, not a provider. Fresh sessions read the root `model_provider`; session metadata then records the chosen provider. Resuming preserves that recorded provider, so a pre-rollout session can stay on ordinary `openai`, while a session created with `openai_api_direct` keeps the direct route and will repeat the 401 until Keychain delivery works. Run the preflight before both paths. After first installing the direct route, start a fresh session rather than using an older ordinary-provider session when the 1M route is required.

## Fleet rollout

Use `$fleet-maintenance` and `$remote-mac` first. Read `~/Projects/manager/computers.yaml`, use live Tailscale state, deduplicate by hardware UUID, and exclude handed-off hosts. Audit all reachable hosts before mutation; mutate one host at a time.

Peter's current personal Mac scope is MacBook Pro, Mac Studio, ClawMac, MegaClaw, and MiniClaw. Verify identity and the `agent-scripts` checkout before changing any remote files. Keep a per-host result with:

- config/catalog installed and both values for all three model entries;
- preflight passed in the intended local user session, or the exact Keychain/local-session blocker;
- `codex login status` result, without showing any credential;
- backup path and whether a desktop restart is pending.

The `agent-scripts` skill checkout is normally exposed by `~/.codex/skills/agent-scripts`. After pushing this skill, fast-forward only eligible `~/Projects/agent-scripts` checkouts. Never reset, stash, or overwrite an active/dirty checkout; report it as pending instead.

## Verification

Run these in the intended local user session:

```zsh
ruby ~/.codex/skills/agent-scripts/codex-huge-context/scripts/preflight.rb
codex login status
jq -r '.models[] | select(.slug == "gpt-5.6-sol" or .slug == "gpt-5.6-terra" or .slug == "gpt-5.6-luna") | [.slug, .context_window, .max_context_window] | @tsv' ~/.codex/models-api-1m.json
codex exec --skip-git-repo-check 'Reply with exactly: direct-api-1m-ok'
```

Expect a successful preflight, `1050000` for both window fields on all three models, and the exact probe response. Restart the Codex desktop app after configuration so its app-server reloads the files. A successful direct API probe does not prove connector OAuth; confirm `codex login status` separately.

## Failure policy

- API response still clamps/rejects a request: record the server response; do not claim a client catalogue override changed server entitlement.
- HTTP 401 `Missing bearer or basic authentication in header`: rerun the preflight and repair Keychain delivery; do not switch providers or ordinary Codex authentication.
- Keychain error 36 remotely: leave the safe configuration staged and require a local GUI unlock. Never weaken secret storage.
- Root API-key login but connectors are required: ask the local user to complete the ChatGPT login; inference can remain on the direct provider.
- Existing `openai_api_direct` provider differs from this contract: inspect it before changing it; do not append a duplicate TOML table.
