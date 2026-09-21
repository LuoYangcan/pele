#!/usr/bin/env bash
# Show the Simulator window for one UDID through the first host `open` accepts.
# Xcode <= 26 bundles Developer/Applications/Simulator.app; Xcode 27 hosts the
# simulator windows in Contents/Applications/DeviceHub.app instead.
set -euo pipefail
udid="${1:?usage: open-simulator.sh <simulator-udid>}"
developer="$(xcode-select -p)"
bundled="$developer/Applications/Simulator.app"
device_hub="$(dirname "$developer")/Applications/DeviceHub.app"

show() {
  if open "$@" --args -CurrentDeviceUDID "$udid"; then
    echo "SIMULATOR_HOST=${*: -1}"
    exit 0
  fi
}

if [ -d "$bundled" ]; then show "$bundled"; fi
show -a Simulator
if [ -d "$device_hub" ]; then show "$device_hub"; fi
echo "ERROR: no Simulator window host accepted -CurrentDeviceUDID $udid" >&2
exit 1
