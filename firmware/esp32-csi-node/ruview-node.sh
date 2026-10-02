#!/usr/bin/env bash
# Manage RuView boards over the air, no cable (2 Oct 2026). Needs each board to
# have been through room-only.sh once (OTA key + 0.8.7).
#
#   ./ruview-node.sh status [1|2|3|all]           firmware version on each board
#   ./ruview-node.sh push   [1|2|3|all] [file.bin] flash build/esp32-csi-node.bin (default)
#   ./ruview-node.sh config <1|2|3> key=value ...  ssid, password, target_ip, target_port,
#                                                  filter_mac, pres_thresh, csi_channel
#
# The boards sit on the mango's ruview-tx LAN behind its NAT, so every call goes
# through an SSH tunnel to the mango (no firewall change on it). Each board's
# address comes from the mango's DHCP leases, matched by MAC.
# Safety is on the board: a new image that never joins Wi-Fi rolls back, and
# settings that cannot connect within 3 minutes are put back.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./room-only.local.sh
ENVF="$HOME/Documents/Claude/Projects/Cleetus V2/cleetus.env"
PSK=$(grep -E '^RUVIEW_OTA_PSK=' "$ENVF" | head -1 | cut -d= -f2-)
[ ${#PSK} = 64 ] || { echo "RUVIEW_OTA_PSK missing from cleetus.env"; exit 1; }
MANGO_SSH=(ssh -o ConnectTimeout=8 -o BatchMode=yes -b 192.168.1.134 root@192.168.2.4)

ip_of() {   # node id -> its ruview-tx address, from the mango's leases
  local m="NODE${1}_MAC"; local mac; mac=$(echo "${!m}" | tr 'A-F' 'a-f')
  "${MANGO_SSH[@]}" cat /tmp/dhcp.leases | awk -v m="$mac" 'tolower($2)==m {print $3}' | head -1
}

TUN_PID=""; PORT=""
tunnel() {  # node id -> PORT (1803N) forwarded to that board's :8032; no subshell, so TUN_PID survives
  local ip; ip=$(ip_of "$1")
  [ -n "$ip" ] || { echo "node $1: not on ruview-tx (no DHCP lease on the mango)"; return 1; }
  PORT=$((18030 + $1))
  "${MANGO_SSH[@]}" -o ExitOnForwardFailure=yes -N -L "$PORT:$ip:8032" </dev/null >/dev/null 2>&1 & TUN_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -m 1 "http://127.0.0.1:$PORT/ota/status" >/dev/null && return 0; sleep 0.5; done
  return 0
}
untunnel() { [ -n "$TUN_PID" ] && kill "$TUN_PID" 2>/dev/null || true; TUN_PID=""; }
trap untunnel EXIT

version() { curl -s -m 5 "http://127.0.0.1:$1/ota/status" | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "?"; }

nodes() { [ "${1:-all}" = all ] && echo "1 2 3" || echo "$1"; }

cmd=${1:-status}; shift || true
case "$cmd" in
  status)
    for n in $(nodes "${1:-all}"); do
      tunnel "$n" || continue; port=$PORT
      echo "node $n: $(curl -s -m 5 "http://127.0.0.1:$port/ota/status")"; untunnel
    done ;;
  push)
    BIN=${2:-build/esp32-csi-node.bin}
    want=$(strings "$BIN" | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+$')
    for n in $(nodes "${1:-all}"); do
      tunnel "$n" || continue; port=$PORT
      echo "node $n: $(version "$port") -> $want, uploading $(wc -c < "$BIN" | tr -d ' ') bytes"
      curl -s -m 180 -X POST "http://127.0.0.1:$port/ota" -H "Authorization: Bearer $PSK" \
        -H "Content-Type: application/octet-stream" --data-binary @"$BIN"; echo; untunnel
      echo "  waiting for it to reboot and rejoin..."; got="?"
      for _ in $(seq 1 24); do sleep 5; tunnel "$n" >/dev/null 2>&1 || continue; port=$PORT; got=$(version "$port"); untunnel; [ "$got" = "$want" ] && break; done
      [ "$got" = "$want" ] && echo "  ✓ node $n runs $got" || echo "  ✗ node $n reports $got (a failed image rolls back by itself)"
    done ;;
  config)
    n=${1:?node id}; shift; [ $# -gt 0 ] || { echo "give key=value settings"; exit 1; }
    tunnel "$n"; port=$PORT; body=$(printf '%s\n' "$@")
    curl -s -m 20 -X POST "http://127.0.0.1:$port/config" -H "Authorization: Bearer $PSK" --data-binary "$body"; echo; untunnel
    echo "  node $n reboots; if the new settings cannot join Wi-Fi it restores the old ones within ~3 min." ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
