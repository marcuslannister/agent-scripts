#!/usr/bin/env bash
set -euo pipefail

host="${1:-192.168.0.1}"
item_id="${2:-2n4prwqn2zbhph3cwfbilgwwte}"
session="${3:-unifi-auth}"
cookie="${UNIFI_COOKIE:-/tmp/unifi-cookie.jar}"
csrf_file="${UNIFI_CSRF:-/tmp/unifi-csrf.txt}"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [[ -z "${TMUX:-}" && "${UNIFI_AUTH_IN_TMUX:-}" != "1" ]]; then
  tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session" -n shell 'zsh -l'
  cmd="clear; UNIFI_AUTH_IN_TMUX=1 $(printf '%q' "$self") $(printf '%q' "$host") $(printf '%q' "$item_id") $(printf '%q' "$session"); tmux clear-history"
  tmux send-keys -t "$session" "$cmd" C-m
  sleep "${UNIFI_AUTH_WAIT:-10}"
  tmux capture-pane -pt "$session" -S -30
  exit 0
fi

if [[ -z "${TMUX:-}" ]]; then
  echo "refusing: op may only run inside tmux" >&2
  exit 2
fi

json="$(op item get "$item_id" --format json)"
username="$(printf '%s' "$json" | jq -r '[.fields[] | select(.purpose=="USERNAME" or .id=="username") | .value][0] // empty')"
password="$(printf '%s' "$json" | jq -r '[.fields[] | select(.purpose=="PASSWORD" or .id=="password") | .value][0] // empty')"
otp="$(op item get "$item_id" --otp)"

rm -f "$cookie" "$csrf_file" /tmp/unifi-login-headers.txt /tmp/unifi-login-body.txt
code="$(
  jq -n --arg username "$username" --arg password "$password" --arg token "$otp" \
    '{username:$username,password:$password,token:$token,rememberMe:true}' |
  curl -sk -c "$cookie" -D /tmp/unifi-login-headers.txt \
    -H 'Content-Type: application/json' \
    -o /tmp/unifi-login-body.txt \
    -w '%{http_code}' \
    --data-binary @- \
    "https://${host}/api/auth/login"
)"

awk 'BEGIN{IGNORECASE=1} /^x-csrf-token:/ {sub(/\r$/,"",$2); print $2}' /tmp/unifi-login-headers.txt > "$csrf_file"
chmod 600 "$cookie" "$csrf_file" /tmp/unifi-login-headers.txt /tmp/unifi-login-body.txt 2>/dev/null || true
echo "login_code=${code}"
