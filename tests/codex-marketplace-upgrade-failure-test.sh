#!/usr/bin/env bash
set -euo pipefail

# ADR-0007: Codex re-clones a whole marketplace repo under a hardcoded fetch
# window, so an oversized upstream (claude-mem, ~330MB) fails identically on
# every attempt. The adapter must report that once, not three times, and must
# still spend its full retry budget on failures that could be transient.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE="$TMP_ROOT/upgrade-failure"
BIN="$FIXTURE/bin"
HOME_DIR="$FIXTURE/home"
DISCOVERY="$FIXTURE/discovery"
ADAPTER="$FIXTURE/agent-tooling/distribution-topology/adapters/plugin-both.sh"
mkdir -p "$FIXTURE/agent-tooling" "$BIN" "$HOME_DIR" "$DISCOVERY"
cp -R "$REPO_ROOT/agent-tooling/distribution-topology" "$FIXTURE/agent-tooling/"
: > "$FIXTURE/empty-plan.tsv"

fail() {
  printf 'codex marketplace upgrade failure: %s\n' "$1" >&2
  exit 1
}

cat > "$FIXTURE/agent-tooling/distribution-topology/registry.json" <<'JSON'
[
  {
    "sourceId": "oversized",
    "classification": "dual-plugin",
    "supportedDestinations": ["claude", "codex"],
    "command": "adapters/plugin-both.sh",
    "stateInspection": "adapter",
    "plugin": {
      "name": "oversized",
      "repo": "example/oversized",
      "marketplaces": {"claude": "oversized", "codex": "oversized"},
      "skills": ["oversized"]
    }
  }
]
JSON

cat > "$BIN/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$HOME/codex-calls.log"
case "$*" in
  'plugin marketplace list --json')
    printf '%s\n' '{"marketplaces":[{"name":"oversized","root":"/tmp/oversized"}]}'
    ;;
  'plugin marketplace upgrade '*)
    cat "$HOME/codex-upgrade-error"
    exit 1
    ;;
  *)
    printf 'unexpected codex call: %s\n' "$*" >&2
    exit 1
    ;;
esac
BASH
chmod +x "$BIN/codex"

export PATH="$BIN:$PATH"
export HOME="$HOME_DIR"
export PLUGIN_RETRY_DELAY_SECONDS=0

run_ensure_marketplace() { # upgrade-error stderr-file
  : > "$HOME_DIR/codex-calls.log"
  printf '%s\n' "$1" > "$HOME_DIR/codex-upgrade-error"
  (
    # shellcheck disable=SC1090
    source "$ADAPTER" oversized "$FIXTURE" "$DISCOVERY" verify \
      "$FIXTURE/empty-plan.tsv" "$HOME_DIR" reconcile
    ensure_marketplace codex
  ) 2>"$2"
}

count_upgrades() {
  grep -Fc 'plugin marketplace upgrade oversized' "$HOME_DIR/codex-calls.log" || true
}

# The deterministic oversized-clone failure is reported once. This is the verbatim
# codex-cli 0.147.0 message for thedotmack/claude-mem.
if run_ensure_marketplace \
  'Failed to upgrade marketplace `oversized`: git clone marketplace source timed out after 30s: Cloning into ... fatal: early EOF' \
  "$FIXTURE/permanent.err"; then
  fail 'ensure_marketplace succeeded despite a failing upgrade'
fi
[ "$(count_upgrades)" = 1 ] || fail "permanent failure retried $(count_upgrades) times"
grep -Fq 'exceeds the Codex fetch window' "$FIXTURE/permanent.err" \
  || fail 'permanent failure lost its explanation'
grep -Fq '0007-oversized-codex-marketplaces' "$FIXTURE/permanent.err" \
  || fail 'permanent failure did not name the ADR'

# Control: a failure that could be transient still gets the full retry budget.
if run_ensure_marketplace 'fatal: could not resolve host: github.com' \
  "$FIXTURE/transient.err"; then
  fail 'ensure_marketplace succeeded despite a failing upgrade'
fi
[ "$(count_upgrades)" = 3 ] || fail "transient failure retried $(count_upgrades) times"

# A bare `early EOF` is flaky transport, not the fetch-window defect: still retried.
if run_ensure_marketplace 'error: RPC failed; fatal: early EOF' \
  "$FIXTURE/flaky.err"; then
  fail 'ensure_marketplace succeeded despite a failing upgrade'
fi
[ "$(count_upgrades)" = 3 ] || fail "flaky-transport failure retried $(count_upgrades) times"
if grep -Fq 'exceeds the Codex fetch window' "$FIXTURE/flaky.err"; then
  fail 'flaky-transport failure was misreported as the fetch-window defect'
fi

printf 'codex marketplace upgrade failure: ok\n'
