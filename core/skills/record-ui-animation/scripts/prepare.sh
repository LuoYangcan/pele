#!/usr/bin/env bash
# record-ui-animation / Step A: prepare
#
# Inputs (env, required):
#   WORKTREE_SLUG    task slug / worktree name (the caller gets it from Root)
#   CASE_SLUG        short name for the animation case (kebab-case; decides the frame subdirectory)
#   DEVICE_UDID      UDID of a booted iOS Simulator
#
# Inputs (env, optional):
#   EXPECTED_DURATION_SECONDS  (default: 3)
#   FRAME_COUNT                (default: 10)
#
# Outputs (printed as KEY=VALUE for caller to eval / parse):
#   RECORDING_PATH=<abs>
#   FRAMES_DIR=<abs>
#   META_PATH=<abs>
#   DEVICE_UDID=<echo>
#   FRAME_COUNT=<echo>
#   EXPECTED_DURATION_SECONDS=<echo>
#
# Errors (printed then exit 1):
#   ERR_FFMPEG_NOT_FOUND
#   ERR_SIM_NOT_BOOTED:<udid> state=<state>
#   ERR_BAD_SLUG:<slug>   slug contains illegal characters

set -euo pipefail

: "${WORKTREE_SLUG:?missing WORKTREE_SLUG}"
: "${CASE_SLUG:?missing CASE_SLUG}"
: "${DEVICE_UDID:?missing DEVICE_UDID — caller must boot/select device first}"
EXPECTED_DURATION_SECONDS="${EXPECTED_DURATION_SECONDS:-3}"
FRAME_COUNT="${FRAME_COUNT:-10}"

if [[ ! "$WORKTREE_SLUG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERR_BAD_SLUG:$WORKTREE_SLUG"
  exit 1
fi
if [[ ! "$CASE_SLUG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERR_BAD_SLUG:$CASE_SLUG"
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ERR_FFMPEG_NOT_FOUND"; exit 1; }

export DEVICE_UDID
state=$(xcrun simctl list devices -j | python3 -c '
import json, os, sys
udid = os.environ["DEVICE_UDID"]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == udid:
            print(device.get("state", ""))
            sys.exit(0)
print("NotFound")
')
if [[ "$state" != "Booted" ]]; then
  echo "ERR_SIM_NOT_BOOTED:$DEVICE_UDID state=$state"
  exit 1
fi

TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR=".reviews/ui-${WORKTREE_SLUG}-${TS}/animation/${CASE_SLUG}"
mkdir -p "$OUT_DIR/frames"

RECORDING_PATH="$(cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")/recording.mp4"
FRAMES_DIR="$(cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")/frames"
META_PATH="$(cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")/meta.json"

echo "RECORDING_PATH=$RECORDING_PATH"
echo "FRAMES_DIR=$FRAMES_DIR"
echo "META_PATH=$META_PATH"
echo "DEVICE_UDID=$DEVICE_UDID"
echo "FRAME_COUNT=$FRAME_COUNT"
echo "EXPECTED_DURATION_SECONDS=$EXPECTED_DURATION_SECONDS"
