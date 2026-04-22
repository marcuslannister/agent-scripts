#!/usr/bin/env bash
set -euo pipefail

timeout="${SONOS_TIMEOUT:-10s}"
ping_count="${PING_COUNT:-10}"
extra_ips="${EXTRA_IPS:-}"

if ! command -v sonos >/dev/null 2>&1; then
  echo "missing: sonos CLI" >&2
  exit 127
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "== discovery =="
sonos discover --timeout "$timeout" 2>/dev/null | tee "$tmp" || true

echo
echo "== firmware =="
{
  awk -F'\t' 'NF >= 2 {print $2}' "$tmp"
  printf '%s\n' $extra_ips
} | awk 'NF && !seen[$1]++' | while read -r ip; do
  xml="$(curl -fsS --max-time 4 "http://${ip}:1400/status/zp" 2>/dev/null || true)"
  [ -n "$xml" ] || continue
  printf '%s\t' "$ip"
  printf '%s' "$xml" | perl -0777 -ne '
    ($z)=/<ZoneName>(.*?)<\/ZoneName>/s;
    ($v)=/<SoftwareVersion>(.*?)<\/SoftwareVersion>/s;
    ($d)=/<SoftwareDate>(.*?)<\/SoftwareDate>/s;
    print join("\t", $z||"?", $v||"?", $d||"?"), "\n";
  '
done

echo
echo "== ping =="
awk -F'\t' 'NF >= 2 {print $2}' "$tmp" | awk '!seen[$1]++' | while read -r ip; do
  stats="$(ping -c "$ping_count" -W 1000 -q "$ip" 2>/dev/null || true)"
  avg="$(printf '%s\n' "$stats" | awk -F'/' '/round-trip|rtt/ {print $5}')"
  loss="$(printf '%s\n' "$stats" | awk -F', ' '/packet loss/ {print $3}')"
  printf '%s\tavg=%s\tloss=%s\n' "$ip" "${avg:-?}" "${loss:-?}"
done

echo
echo "== groups =="
sonos group status --timeout "$timeout" 2>/dev/null || true
