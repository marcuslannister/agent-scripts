#!/usr/bin/env bash
# Self-check for wait-settled.sh with a fake herdr that replays a list of states.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
cat > "$tmp/herdr" <<'EOF'
#!/usr/bin/env bash
# Print the next state from $STATES (one per call); "gone" fails like agent_not_found.
n=$(cat "$COUNTER" 2>/dev/null || echo 0); echo $((n + 1)) > "$COUNTER"
read -ra s <<< "$STATES"; st="${s[$n]:-${s[-1]}}"
[ "$st" = gone ] && exit 1
printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$st"
EOF
chmod +x "$tmp/herdr"
fail=0
check() { # check <expected exit> <timeout min> <states...>
  local want="$1" tmo="$2"; shift 2
  rm -f "$tmp/count"
  local got=0
  PATH="$tmp:$PATH" COUNTER="$tmp/count" STATES="$*" WAIT_SETTLED_INTERVAL=0 \
    bash "$here/wait-settled.sh" a "$tmo" >/dev/null || got=$?
  if [ "$got" = "$want" ]; then echo "ok   $want <- $*"; else echo "FAIL want $want got $got <- $*"; fail=1; fi
}
check 0 1 working idle working idle idle idle   # a short pause does not count
check 0 1 done done done
check 2 1 working blocked
check 3 1 working gone
check 4 0 working                                # timeout 0 ends after one check
exit "$fail"
