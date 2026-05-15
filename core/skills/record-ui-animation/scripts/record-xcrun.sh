#!/usr/bin/env bash
# record-ui-animation / Step B (xcrun backend, optional fallback)
#
# 用于 caller 不在 mcp env 里、没法调 mobile-mcp 时的录屏路径。
# 与 mobile-mcp 模板二选一。
#
# 用法：
#   1. caller 在前台跑此脚本，脚本会 fork simctl io 到后台并打印 PID
#   2. caller 拿 PID 自己驱动动画
#   3. caller 调 stop-xcrun.sh 传 PID 结束录屏
#
# Inputs (env):
#   DEVICE_UDID
#   RECORDING_PATH
#
# Outputs:
#   REC_PID=<pid>
#   REC_STARTED_AT=<unix-ts>

set -euo pipefail
: "${DEVICE_UDID:?}"
: "${RECORDING_PATH:?}"

if [[ ! "$RECORDING_PATH" =~ \.mp4$ ]]; then
  echo "ERR_RECORDING_PATH_MUST_BE_MP4:$RECORDING_PATH"
  exit 1
fi

# h264 抽帧比 hevc 快一点 + 与 ffmpeg/videotoolbox 兼容性最佳。
# 关键：把 simctl 的 stdout/stderr 重定向到 log 文件，**否则**当 caller
# 用 `eval "$(record-xcrun.sh)"` 调本脚本时，simctl 后台进程会持有父 shell
# 的 fd → command substitution 永远等不到 EOF、整段 eval 卡死。
LOG_PATH="${RECORDING_PATH%.mp4}.simctl.log"
xcrun simctl io "$DEVICE_UDID" recordVideo --codec=h264 --force "$RECORDING_PATH" \
  </dev/null >"$LOG_PATH" 2>&1 &
REC_PID=$!
disown 2>/dev/null || true

# 等 simctl 写出 first frame 再返回（避免 caller 0 延迟点动作、漏掉头几帧）
sleep 0.6

if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "ERR_SIMCTL_DIED_EARLY: recordVideo 在第一帧前就退出 (log=${LOG_PATH})"
  exit 1
fi

echo "REC_PID=$REC_PID"
echo "REC_STARTED_AT=$(date +%s)"
echo "REC_LOG=$LOG_PATH"
