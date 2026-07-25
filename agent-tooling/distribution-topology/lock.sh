#!/usr/bin/env bash

TOPOLOGY_LOCK_PATH=
TOPOLOGY_RECOVERED_PID=
TOPOLOGY_RECOVERED_PENDING=0

topology_process_is_alive() { # pid
  kill -0 "$1" 2>/dev/null
}

topology_pending_lock_is_stale() { # lock_path
  local modified now
  if stat -f %m "$1" >/dev/null 2>&1; then
    modified="$(stat -f %m "$1")"
  else
    modified="$(stat -c %Y "$1" 2>/dev/null || true)"
  fi
  [[ "$modified" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  [ $((now - modified)) -ge 5 ]
}

topology_cleanup_stale_discovery() {
  local candidate
  shopt -s nullglob
  for candidate in "${TMPDIR:-/tmp}"/agent-scripts-topology-discovery-*; do
    rm -rf -- "$candidate"
  done
  shopt -u nullglob
}

topology_acquire_lock() {
  local lock_root pid recovered
  lock_root="${TMPDIR:-/tmp}/agent-scripts-skill-topology-$(id -u 2>/dev/null || printf user).lock"

  while ! mkdir "$lock_root" 2>/dev/null; do
    pid="$(sed -n '1p' "$lock_root/pid" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
      for _ in {1..100}; do
        sleep 0.01
        pid="$(sed -n '1p' "$lock_root/pid" 2>/dev/null || true)"
        [ -n "$pid" ] && break
        [ -d "$lock_root" ] || break
      done
    fi
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && topology_process_is_alive "$pid"; then
      topology_fail 1 "skill topology is already running (PID $pid)"
      return 1
    fi
    recovered="${TMPDIR:-/tmp}/agent-scripts-skill-topology-$(id -u 2>/dev/null || printf user).recovered-$$-$RANDOM"
    if [ -z "$pid" ]; then
      if topology_pending_lock_is_stale "$lock_root"; then
        mv "$lock_root" "$recovered" 2>/dev/null || true
        continue
      fi
      topology_fail 1 "skill topology is already running (PID pending)"
      return 1
    fi

    mv "$lock_root" "$recovered" 2>/dev/null || true
  done

  shopt -s nullglob
  for recovered in "${TMPDIR:-/tmp}"/agent-scripts-skill-topology-*.recovered-*; do
    pid="$(sed -n '1p' "$recovered/pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      [ -n "$TOPOLOGY_RECOVERED_PID" ] || TOPOLOGY_RECOVERED_PID="$pid"
    else
      TOPOLOGY_RECOVERED_PENDING=1
    fi
    rm -rf -- "$recovered"
    topology_cleanup_stale_discovery
  done
  shopt -u nullglob

  TOPOLOGY_LOCK_PATH="$lock_root"
  printf '%s\n' "$$" > "$lock_root/pid"
}

topology_release_lock() {
  [ -n "$TOPOLOGY_LOCK_PATH" ] || return 0
  if [ "$(sed -n '1p' "$TOPOLOGY_LOCK_PATH/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf -- "$TOPOLOGY_LOCK_PATH"
  fi
  TOPOLOGY_LOCK_PATH=
}
