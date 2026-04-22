#!/usr/bin/env bash
set -euo pipefail

host="${1:-192.168.0.1}"
site="${2:-default}"
cookie="${UNIFI_COOKIE:-/tmp/unifi-cookie.jar}"
csrf_file="${UNIFI_CSRF:-/tmp/unifi-csrf.txt}"

if [[ ! -s "$cookie" ]]; then
  echo "missing UniFi cookie; run scripts/unifi-auth-tmux.sh ${host}" >&2
  exit 2
fi

csrf="$(cat "$csrf_file" 2>/dev/null || true)"
headers=()
[ -n "$csrf" ] && headers=(-H "x-csrf-token: $csrf")

api() {
  curl -sk -b "$cookie" "${headers[@]}" "https://${host}/proxy/network/api/s/${site}/$1"
}

dev="$(mktemp)"
sta="$(mktemp)"
wlan="$(mktemp)"
net="$(mktemp)"
trap 'rm -f "$dev" "$sta" "$wlan" "$net"' EXIT

api stat/device > "$dev"
api stat/sta > "$sta"
api rest/wlanconf > "$wlan"
api rest/networkconf > "$net"

echo "== ap radios =="
jq -r '
  .data[]
  | select((.radio_table // []) | length > 0)
  | [
      .name,.model,.type,.mac,.ip,.state,
      (.uplink.type // ""),(.uplink.uplink_mac // ""),(.uplink.signal // ""),
      ([.radio_table_stats[]?
        | select(.radio=="ng" or .radio=="na")
        | "\(.radio):bw=\(.channel_width // .bw // "?"):ch=\(.channel):util=\(.cu_total // .cu_self // "?"):sat=\(.satisfaction // ""):txretry=\(.tx_retries // .tx_retry // "")"
       ] | join(" "))
    ] | @tsv
' "$dev"

echo
echo "== sonos clients =="
jq -r --slurpfile devices "$dev" '
  ($devices[0].data | map(select(.mac) | {key:.mac, value:.name}) | from_entries) as $aps
  | .data[]
  | select((.oui // .hostname // .name // "") | test("Sonos|SonosZP"; "i"))
  | [
      .mac, (.name // .hostname // ""), (.ip // ""),
      ($aps[.ap_mac] // .ap_mac), .radio, .channel, .signal,
      .tx_rate, .rx_rate, (.tx_retries // .tx_retry // ""), (.satisfaction // "")
    ] | @tsv
' "$sta"

echo
echo "== sonos by ap/radio =="
jq -r '
  [.data[] | select((.oui // .hostname // .name // "") | test("Sonos|SonosZP"; "i"))]
  | group_by(.ap_mac + ":" + (.radio // ""))
  | .[]
  | [
      .[0].ap_mac, .[0].radio, length,
      (([.[].signal] | add / length) | floor),
      (([.[].rx_rate] | add / length) | floor),
      ([.[].tx_retries // 0] | add)
    ] | @tsv
' "$sta"

echo
echo "== wlan flags =="
jq -r '
  .data[]
  | select(.enabled==true)
  | [
      .name,.is_guest,.security,.wpa_mode,.wpa3_support,.wpa3_transition,.pmf_mode,
      .fast_roaming_enabled,.bss_transition,.uapsd_enabled,.proxy_arp,.mcastenhance_enabled,
      .dtim_ng,.dtim_na,.bandsteering_mode,.ap_group_mode,((.wlan_bands // [])|join(","))
    ] | @tsv
' "$wlan"

echo
echo "== networks =="
jq -r '
  .data[]
  | [.name,.purpose,.ip_subnet,.dhcpd_enabled,.igmp_snooping,.mdns_enabled,.ipv6_interface_type]
  | @tsv
' "$net"
