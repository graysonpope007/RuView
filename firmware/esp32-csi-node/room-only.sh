#!/usr/bin/env bash
# Move ONE plugged-in RuView board to "room only" (2 Oct 2026): join the mango's
# ruview-tx (the in-room transmitter at the desk) instead of the house router
# downstairs, sense the mango as its primary, and flash the firmware whose
# allowlist no longer contains the house router. Node 2 was already on ruview-tx.
#
#   ./room-only.sh            (exactly one board plugged in; found by its MAC)
#
# Every NVS field is passed explicitly, from each board's own 0.8.5 boot log,
# so provision.py cannot drop node id, TDM slot or the pinned presence threshold.
set -euo pipefail
cd "$(dirname "$0")"
ENVF="$HOME/Documents/Claude/Projects/Cleetus V2/cleetus.env"
KEY=$(grep -E '^MANGO_WIFI_KEY=' "$ENVF" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
[ -n "$KEY" ] || { echo "MANGO_WIFI_KEY missing from cleetus.env"; exit 1; }
# MACs live in room-only.local.sh (git-ignored; see room-only.local.example.sh):
# the mango is an access point, and an AP's MAC can be looked up in public
# Wi-Fi location databases.
# shellcheck disable=SC1091
source ./room-only.local.sh

line=$(ioreg -r -c IOUSBHostDevice -l -w0 | awk '/"USB Serial Number"/{sn=$NF} /"IOCalloutDevice"/{print sn,$NF}' | tr -d '"' | grep -E "^($NODE1_MAC|$NODE2_MAC|$NODE3_MAC) " || true)
[ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || { echo "Plug in exactly ONE board. Saw: ${line:-none}"; exit 1; }
MAC=${line%% *}; PORT=${line##* }
for i in 1 2 3; do
  m="NODE${i}_MAC"
  if [ "$MAC" = "${!m}" ]; then
    ID=$i; s="NODE${i}_SLOT"; p="NODE${i}_PRES"; w="NODE${i}_WHERE"
    SLOT=${!s}; PRES=${!p}; WHERE=${!w}
  fi
done
echo "→ node $ID ($WHERE) on $PORT"

export IDF_PATH="$HOME/esp/esp-idf-v5.4.1" IDF_PYTHON_ENV_PATH="$HOME/.espressif/python_env/idf5.4_py3.12_env"
export PATH="/opt/homebrew/opt/python@3.12/bin:$PATH"
# shellcheck disable=SC1091
source "$IDF_PATH/export.sh" >/dev/null

if [ "$ID" != 2 ]; then
  python provision.py --port "$PORT" --ssid ruview-tx --password "$KEY" \
    --target-ip 192.168.2.1 --target-port 5005 --node-id "$ID" \
    --tdm-slot "$SLOT" --tdm-total 3 --edge-tier 2 --pres-thresh "$PRES" \
    --filter-mac "$MANGO" --reset
fi
idf.py -p "$PORT" app-flash
echo "✓ node $ID done. Put it back ($WHERE)."
