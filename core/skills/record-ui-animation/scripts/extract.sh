#!/usr/bin/env bash
# record-ui-animation / Step C: extract frames
#
# Inputs (env):
#   RECORDING_PATH
#   FRAMES_DIR
#   META_PATH
#   FRAME_COUNT    (default 10)
#   SCALE          (default 0.5 — 1206x2622 @3x → ~603x1311 ~700KB/帧;
#                   传 1.0 拿原分辨率，pixel-精度对比时用)
#
# Outputs:
#   FRAMES_DIR=<abs>
#   FRAMES=<actual count>
#   RECORDING_DURATION_SECONDS=<float>
#   META_PATH=<abs>

set -euo pipefail
: "${RECORDING_PATH:?}"
: "${FRAMES_DIR:?}"
: "${META_PATH:?}"
FRAME_COUNT="${FRAME_COUNT:-10}"
SCALE="${SCALE:-0.5}"

command -v ffmpeg  >/dev/null || { echo "ERR_FFMPEG_NOT_FOUND"; exit 1; }
command -v ffprobe >/dev/null || { echo "ERR_FFPROBE_NOT_FOUND"; exit 1; }

[[ -f "$RECORDING_PATH" ]] || { echo "ERR_RECORDING_MISSING:$RECORDING_PATH"; exit 1; }

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RECORDING_PATH" || true)
if [[ -z "$DURATION" || "$DURATION" == "N/A" ]]; then
  echo "ERR_FFPROBE_NO_DURATION:$RECORDING_PATH"
  exit 1
fi

# 防 0 时长（录屏立刻被打断 → ffprobe 给个非常小的数）
if python3 -c "import sys; sys.exit(0 if float('$DURATION') < 0.1 else 1)"; then
  echo "ERR_RECORDING_TOO_SHORT:duration=$DURATION (caller 应延长 sleep)"
  exit 1
fi

# fps = FRAME_COUNT / DURATION；后接 -frames:v 限上限避免边界帧多出来一两张
FPS=$(python3 -c "print(round(${FRAME_COUNT}/float('${DURATION}'), 4))")

# 清空旧 frames（同 CASE_SLUG 重跑时）
rm -f "$FRAMES_DIR"/frame-*.png

ffmpeg -y -loglevel error \
  -i "$RECORDING_PATH" \
  -vf "fps=${FPS},scale=iw*${SCALE}:ih*${SCALE}:flags=lanczos" \
  -frames:v "$FRAME_COUNT" \
  "$FRAMES_DIR/frame-%03d.png"

ACTUAL=$(find "$FRAMES_DIR" -name 'frame-*.png' -type f | wc -l | tr -d ' ')

if [[ "$ACTUAL" -lt 2 ]]; then
  echo "ERR_FRAME_COUNT_TOO_LOW:got $ACTUAL frames (expected ~$FRAME_COUNT) — recording 可能损坏"
  exit 1
fi

python3 - <<PY > "$META_PATH"
import json
print(json.dumps({
    "recording_path": "$RECORDING_PATH",
    "frames_dir": "$FRAMES_DIR",
    "frame_count_requested": $FRAME_COUNT,
    "frame_count_actual": $ACTUAL,
    "duration_seconds": float("$DURATION"),
    "extraction_fps": $FPS,
    "scale": $SCALE,
}, indent=2))
PY

echo "FRAMES_DIR=$FRAMES_DIR"
echo "FRAMES=$ACTUAL"
echo "RECORDING_DURATION_SECONDS=$DURATION"
echo "META_PATH=$META_PATH"
