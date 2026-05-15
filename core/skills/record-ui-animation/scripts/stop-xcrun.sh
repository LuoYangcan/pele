#!/usr/bin/env bash
# record-ui-animation / Step B 收尾（xcrun backend）
#
# Inputs (env):
#   REC_PID            record-xcrun.sh 输出的 PID
#   RECORDING_PATH     用于校验文件是否真的写出
#
# Outputs:
#   RECORDING_SIZE=<bytes>
#   RECORDING_PATH=<abs>

set -euo pipefail
: "${REC_PID:?}"
: "${RECORDING_PATH:?}"

if kill -0 "$REC_PID" 2>/dev/null; then
  # SIGINT 让 simctl finalize mp4 + 写 moov atom，不要 SIGTERM/KILL（产物会损坏）
  kill -INT "$REC_PID"
  # `wait $PID` 在 PID 不是当前 shell 的 child 时立刻返回（命令替换里 fork 出的进程
  # 属于父 shell、不是 stop 脚本的 child），所以这里改成 poll `kill -0` 直到进程退出。
  # simctl finalize 一般 <2s；给 10s 兜底，超时也不强杀（强杀=损坏 mp4）。
  for _ in $(seq 1 50); do
    kill -0 "$REC_PID" 2>/dev/null || break
    sleep 0.2
  done
fi

[[ -f "$RECORDING_PATH" ]] || { echo "ERR_RECORDING_MISSING:$RECORDING_PATH"; exit 1; }

SIZE=$(stat -f%z "$RECORDING_PATH" 2>/dev/null || stat -c%s "$RECORDING_PATH")
if [[ "$SIZE" -lt 1024 ]]; then
  echo "ERR_RECORDING_TOO_SMALL:$SIZE bytes (mp4 corrupt or premature SIGINT)"
  exit 1
fi

echo "RECORDING_SIZE=$SIZE"
echo "RECORDING_PATH=$RECORDING_PATH"
