#!/usr/bin/env bash
# The LAST USB session for a RuView board (2 Oct 2026). Moves it to "room only": join the mango's
# ruview-tx (the in-room transmitter at the desk) instead of the house router
# downstairs, sense the mango as its primary, and flash the firmware whose
# allowlist no longer contains the house router, AND turns on over-the-air
# updates: an OTA key (RUVIEW_OTA_PSK in cleetus.env) plus 0.8.7 (rollback-
# enabled bootloader, no 900 KB cap, POST /config). After this, use
# ruview-node.sh for firmware and settings; no cable.
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
PSK=$(grep -E '^RUVIEW_OTA_PSK=' "$ENVF" | head -1 | cut -d= -f2-)
[ ${#PSK} = 64 ] || { echo "RUVIEW_OTA_PSK missing from cleetus.env"; exit 1; }
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

# Settings: room-only Wi-Fi + the OTA key, in ONE image (it replaces the whole
# NVS partition). Node 2's stale csi_channel=1 is not carried over.
python provision.py --port "$PORT" --ssid ruview-tx --password "$KEY" \
  --target-ip 192.168.2.1 --target-port 5005 --node-id "$ID" \
  --tdm-slot "$SLOT" --tdm-total 3 --edge-tier 2 --pres-thresh "$PRES" \
  --filter-mac "$MANGO" --ota-psk "$PSK" --reset
# FULL flash, not app-only: the bootloader has to be the rollback-enabled one
# (0.8.7) for over-the-air updates to be safe. NVS at 0x9000 is not touched.
idf.py -p "$PORT" flash
echo "✓ node $ID done. Put it back ($WHERE)."
