#!/usr/bin/env bash
# Flash the already-built reconnect-forever firmware onto ONE RuView node,
# app partition only (NVS, i.e. its Wi-Fi + target settings, is kept).
#
#   1. Plug the node into the Mac with a DATA USB-C cable.
#   2. ./flash-app-only.sh            (finds the one new /dev/cu.usbmodem*)
#      ./flash-app-only.sh /dev/cu.usbmodemXXXX   (if more than one is plugged in)
#   3. Unplug it, put it back on its charger, and it rejoins ruview-tx.
#
# Built with ESP-IDF 5.4.1 (see handoff s176). Nothing is rebuilt here unless
# the binary is missing, so the bytes flashed are the ones node 2 already runs.
set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-}"
if [ -z "$PORT" ]; then
  ports=($(ls /dev/cu.usbmodem* 2>/dev/null || true))
  if [ "${#ports[@]}" -ne 1 ]; then
    echo "Expected exactly one /dev/cu.usbmodem* and found ${#ports[@]}: ${ports[*]:-none}."
    echo "Plug in one node (data cable), or pass the port: $0 /dev/cu.usbmodemXXXX"
    exit 1
  fi
  PORT="${ports[0]}"
fi
echo "→ node on $PORT"

export IDF_PATH="$HOME/esp/esp-idf-v5.4.1"
export IDF_PYTHON_ENV_PATH="$HOME/.espressif/python_env/idf5.4_py3.12_env"
export PATH="/opt/homebrew/opt/python@3.12/bin:$PATH"
# shellcheck disable=SC1091
source "$IDF_PATH/export.sh" >/dev/null

[ -f build/esp32-csi-node.bin ] || idf.py build
idf.py -p "$PORT" app-flash
echo "✓ flashed. Unplug it and put it back; it should show in the RuView roster within a minute."
