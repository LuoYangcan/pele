---
name: record-ui-animation
description: Capture iOS Simulator motion through xcrun as keyframe PNGs for animation and transition inspection. Skip static UI, Android, real devices, and desktop targets.
---

# Record UI animation

This skill only captures an iOS Simulator recording and its keyframes; the caller handles navigation, the single trigger action and the PASS/FAIL judgment.

## Inputs and outputs

Required: `WORKTREE_SLUG`, `CASE_SLUG` and the `DEVICE_UDID` of a booted iOS Simulator. Optional: `EXPECTED_DURATION_SECONDS` (default 3), `FRAME_COUNT` (default 10) and the frame `SCALE` (default 0.5). Output goes to `.reviews/ui-<slug>-<timestamp>/animation/<case>/`: `recording.mp4`, `frames/` and `meta.json`.

## Capture

```bash
eval "$(WORKTREE_SLUG="$WORKTREE_SLUG" CASE_SLUG="$CASE_SLUG" \
  DEVICE_UDID="$DEVICE_UDID" \
  EXPECTED_DURATION_SECONDS="${EXPECTED_DURATION_SECONDS:-3}" \
  FRAME_COUNT="${FRAME_COUNT:-10}" \
  bash "$HARNESS_ROOT/core/skills/record-ui-animation/scripts/prepare.sh")"

eval "$(DEVICE_UDID="$DEVICE_UDID" RECORDING_PATH="$RECORDING_PATH" \
  bash "$HARNESS_ROOT/core/skills/record-ui-animation/scripts/record-xcrun.sh")"

# The caller performs the single trigger action from the final plan inside the recording window.
sleep <expected-duration-plus-buffer>

REC_PID="$REC_PID" RECORDING_PATH="$RECORDING_PATH" \
  bash "$HARNESS_ROOT/core/skills/record-ui-animation/scripts/stop-xcrun.sh"

RECORDING_PATH="$RECORDING_PATH" FRAMES_DIR="$FRAMES_DIR" META_PATH="$META_PATH" \
  FRAME_COUNT="${FRAME_COUNT:-10}" SCALE="${SCALE:-0.5}" \
  bash "$HARNESS_ROOT/core/skills/record-ui-animation/scripts/extract.sh"
```

The record script runs `xcrun simctl io <UDID> recordVideo --codec=h264 --force <path>` and stops it with SIGINT so simctl finishes writing the MP4. With fewer than 2 frames, missing keyframes or a failed recording, record an environment limitation; retry once only after fixing a specific environmental cause.

Do not boot, build, install, launch, navigate, tap, type or change Simulator settings; do not produce GIFs or reuse a recording across devices. Static size/color checks use the screenshot path, not recording.
