---
name: record-ui-animation
description: Capture iOS/Android Simulator motion as keyframe PNGs for agent inspection. Use for animation, transition, morph, loading, gesture, keyboard, toast, sheet, or other time-dependent UI evidence. Skip static UI, pure logic, real devices, and desktop targets.
---

# Record UI animation

本 skill 只采集录屏和关键帧，不负责导航、触发动作或判定 PASS/FAIL。caller 按最终 plan 的动态用例驱动 app，并读取帧序列判断。

## Inputs

| 变量 | 要求 |
| --- | --- |
| `WORKTREE_SLUG` | 必填，安全的短标识 |
| `CASE_SLUG` | 必填，kebab-case 用例名 |
| `DEVICE_UDID` | 必填，目标 Simulator/emulator |
| `EXPECTED_DURATION_SECONDS` | 默认 3 |
| `FRAME_COUNT` | 默认 10；短动画 6–8，长动画 10–15 |
| `PLATFORM` | 默认 `ios`；可选 `android` |

输出目录为 `.reviews/ui-<slug>-<timestamp>/animation/<case>/`。

## Capture lifecycle

### Prepare

```bash
eval "$(WORKTREE_SLUG="$WORKTREE_SLUG" CASE_SLUG="$CASE_SLUG" \
  DEVICE_UDID="$DEVICE_UDID" \
  EXPECTED_DURATION_SECONDS="${EXPECTED_DURATION_SECONDS:-3}" \
  FRAME_COUNT="${FRAME_COUNT:-10}" PLATFORM="${PLATFORM:-ios}" \
  bash ~/.claude/skills/record-ui-animation/scripts/prepare.sh)"
```

返回 `RECORDING_PATH`、`FRAMES_DIR`、`META_PATH` 和 `DEVICE_UDID`。依赖或 device 校验失败时按脚本错误码降级。

### Record, act, stop

到达动画起点后再起录；导航动作不要混入被测时间窗。

```bash
eval "$(DEVICE_UDID="$DEVICE_UDID" RECORDING_PATH="$RECORDING_PATH" \
  bash ~/.claude/skills/record-ui-animation/scripts/record-xcrun.sh)"

# caller 在这里执行最终 plan 指定的唯一触发动作；每个 sim-use 都带 --device。

sleep <expected-duration-plus-buffer>

REC_PID="$REC_PID" RECORDING_PATH="$RECORDING_PATH" \
  bash ~/.claude/skills/record-ui-animation/scripts/stop-xcrun.sh
```

`stop-xcrun.sh` 使用 SIGINT 让 simctl finalize MP4；不要改用 SIGTERM/KILL。

### Extract

```bash
RECORDING_PATH="$RECORDING_PATH" FRAMES_DIR="$FRAMES_DIR" \
  META_PATH="$META_PATH" FRAME_COUNT="${FRAME_COUNT:-10}" SCALE=0.5 \
  bash ~/.claude/skills/record-ui-animation/scripts/extract.sh
```

返回 `FRAMES_DIR`、实际帧数、时长和 `META_PATH`。默认 0.5 scale 控制多图 context 体积；像素级问题才用 1.0。

## 判定交接

caller 读取全部输出帧，对照用例的起始、中间、结束状态和时序，返回证据路径与观察。帧少于 2、关键帧缺失或录制失败时记环境限制；只有在发现并修正具体环境原因后才重试一次，不能盲录。

## 约束

- 不自动 boot、build、install 或 launch app。
- 不点击、输入、滑动或修改 Simulator 设置；这些由 caller 在录制窗口内按用例执行。
- 不判断动画、不生成 GIF、不跨 device 共享一次录制。
- 静态 frame/间距/颜色使用 screenshot 路径，不录屏。
