---
name: one-password
description: 1Password CLI/op: desktop sign-in, account choice, targeted secret read/store/inject. tmux-only op commands.
metadata: {"clawdbot":{"emoji":"🔐","requires":{"bins":["op"]},"install":[{"id":"brew","kind":"brew","formula":"1password-cli","bins":["op"],"label":"Install 1Password CLI (brew)"}]}}
---

# 1Password CLI

Follow the official CLI get-started steps. Don't guess install commands.

## References

- Official docs: https://developer.1password.com/docs/cli/get-started/
- `references/get-started.md` (install + app integration + sign-in flow)
- `references/cli-examples.md` (real `op` examples, including safe item create/edit patterns)

## Workflow

1. Check OS + shell.
2. Verify CLI present inside tmux: `op --version`.
3. Confirm desktop app integration is enabled (per get-started) and the app is unlocked.
4. REQUIRED: create a fresh tmux session for all `op` commands (no direct `op` calls outside tmux).
5. Sign in / authorize inside tmux: `op signin` (expect app prompt).
6. Verify access inside tmux: `op whoami` (must succeed before any secret read).
7. If multiple accounts: use `--account` or `OP_ACCOUNT`.

## Peter account defaults

- Peter's default account for personal/work secrets is `my.1password.com` ("Peter Steinberger's Clan").
- Do not silently use `my.1password.eu` / Titan unless Peter asks for it.
- Pass `--account my.1password.com` on every `op` command when storing or reading Peter's secrets. Do not rely on ambient account selection.
- `op account list` is metadata-only, but still must run inside tmux. Use it to confirm account names when routing is unclear.
- `op signin --account my.1password.com` can return status 0 with no useful output and still not make a later shell signed in. Prefer doing sign-in, create/edit/get, and verification in the same tmux shell.

## Service account tokens

- 1Password service accounts are non-interactive tokens for a specific vault/scope, useful for automation without unlocking the desktop app.
- The current service-account env var is `MOLTY_OP_SERVICE_ACCOUNT_TOKEN` in `~/.profile`; use it only for known items in the restricted `Molty` vault.
- Check `~/.profile` first for service-account tokens before asking the user to unlock the 1Password desktop app.
- Export it only for the single command that needs it: `OP_SERVICE_ACCOUNT_TOKEN="$MOLTY_OP_SERVICE_ACCOUNT_TOKEN" op item get "<known item>" --vault Molty ...`.
- Service-account `op` reads require an explicit vault query; omitting `--vault Molty` fails even when the token is valid.
- Keep the tmux rule: every `op` command, including service-account reads, still runs inside one named tmux session.
- Do not enumerate vaults/items with service accounts. If the known item or field is not accessible, stop and ask the user instead of probing.
- Print presence/shape only, never token or secret values.

## REQUIRED tmux session (T-Max)

The shell tool uses a fresh TTY per command. To avoid re-prompts and failures, always run `op` inside a dedicated tmux session with a fresh socket/session name.

Example (see `tmux` skill for socket conventions, do not reuse old session names):

```bash
SOCKET_DIR="${CLAWDBOT_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/clawdbot-tmux-sockets}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/clawdbot-op.sock"
SESSION="op-auth-$(date +%Y%m%d-%H%M%S)"

tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- "op signin --account my.1password.com" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- "op whoami" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- "op vault list" Enter
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -200
tmux -S "$SOCKET" kill-session -t "$SESSION"
```

## Known working secret-write pattern

Use a fresh tmux session, read the secret from the clipboard without printing it, optionally validate an expected token prefix, and write to Peter's account explicitly. The `op` category string is human-readable and case-sensitive in this CLI build; use `"API Credential"`, not `api_credential`.

```bash
tmux new-session -d -s op-store-secret 'bash -lc '\''set -euo pipefail
set +x
ACCOUNT="my.1password.com"
ITEM_TITLE="Service API Tokens"
FIELD_NAME="api_token"
EXPECTED_PREFIX=""
NOTES="Created via tmux-safe op workflow"
TOKEN="$(pbpaste)"
if [ -n "$EXPECTED_PREFIX" ]; then
  case "$TOKEN" in "$EXPECTED_PREFIX"*) ;; *) echo "clipboard value does not match expected prefix" >&2; exit 2;; esac
fi
op item create --account "$ACCOUNT" --category "API Credential" --title "$ITEM_TITLE" "$FIELD_NAME[password]=$TOKEN" "notesPlain=$NOTES" >/dev/null
op item get "$ITEM_TITLE" --account "$ACCOUNT" --fields "label=$FIELD_NAME" >/dev/null
echo "stored and verified secret field without printing it"
sleep 30
'\'''
```

For a second secret on the same item:

```bash
tmux new-session -d -s op-edit-secret 'bash -lc '\''set -euo pipefail
set +x
ACCOUNT="my.1password.com"
ITEM_TITLE="Service API Tokens"
FIELD_NAME="app_token"
EXPECTED_PREFIX=""
TOKEN="$(pbpaste)"
if [ -n "$EXPECTED_PREFIX" ]; then
  case "$TOKEN" in "$EXPECTED_PREFIX"*) ;; *) echo "clipboard value does not match expected prefix" >&2; exit 2;; esac
fi
op item edit "$ITEM_TITLE" --account "$ACCOUNT" "$FIELD_NAME[password]=$TOKEN" >/dev/null
op item get "$ITEM_TITLE" --account "$ACCOUNT" --fields "label=$FIELD_NAME" >/dev/null
echo "stored and verified secret field without printing it"
sleep 30
'\'''
```

## Redacted debugging

Keep the whole pipeline inside tmux. Inspect status and output length, never secret values.

```bash
tmux new-session -d -s op-debug 'bash -lc '\''set -euo pipefail
set +x
SIGNIN_OUTPUT="$(op signin --account my.1password.com 2>&1 || true)"
echo "signin output bytes: ${#SIGNIN_OUTPUT}"
op account list 2>&1 | sed -E "s/(xox[baprs]-)[A-Za-z0-9-]+/\\1REDACTED/g; s/(xapp-)[A-Za-z0-9-]+/\\1REDACTED/g"
sleep 30
'\'''
```

## Guardrails

- Never paste secrets into logs, chat, or code.
- Prefer `op run` / `op inject` over writing secrets to disk.
- If sign-in without app integration is needed, use `op account add`.
- If a command returns "account is not signed in", re-run `op signin` inside tmux and authorize in the app.
- Do not run `op` outside tmux; stop and ask if tmux is unavailable.
