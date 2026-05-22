---
name: record-ui-animation
description: Record an iOS / Android Simulator screen, then extract evenly-spaced keyframe PNGs (default 10 frames) that an agent can Read to visually inspect motion a single screenshot can't capture. Use whenever a UI verification case or user request mentions "动画 / animation / 过渡 / transition / 飞行 / fly / morph / 缩放 / scale / 淡入淡出 / fade / 滑出 / dismiss / 弹出 / 录屏" — even if the user doesn't explicitly say "record". The skill ONLY captures evidence (recording + frame extraction) — caller drives the actual animation trigger (tap / type / swipe), and caller / agent reads the frames to judge. Skip for static UI (single screenshot is enough), pure logic verification, non-Simulator targets (real device / macOS app).
---

# record-ui-animation

录一段 iOS / Android Simulator 屏幕 → ffmpeg 抽 N 帧 PNG → 让 agent 自己 Read 看动画对不对。**只采集证据**，不点击 / 不输入 / 不判断

## 触发

满足**任一**条件：

- spec 第 4 节 / 用户原话里出现「动画 / animation / transition / 过渡 / 飞行 / fly / morph / 缩放 / 淡入淡出 / fade / 滑出 / dismiss / 弹出 / 录屏」
- executor 跑 iOS UI 冒烟时遇到「动态用例」—— 原本要走 `ui_dynamic_cases_skipped` 让用户自己看，改用本 skill 自动采集
- generator 刚写完动画代码、想自己快速对照效果验真
- 主 agent 收到「帮我看一下这个动画走起来对不对」类请求且代码已 build + simulator 已 boot

## 不触发

- 静态 UI / 间距 / 字号 / 颜色 / 布局核对 → 一张 `mobile_take_screenshot` 就够，**不要**为了"更安全"无脑录屏
- 纯逻辑 / 数据 / 网络验证 → 没视觉成分，录屏没意义
- 真机 / macOS app / Apple Watch / TV → 本 skill 只覆盖 iOS Simulator + Android emulator
- caller 还没把 simulator boot 起来 / app 装上 / 走到动画起点 → 先走 `find-ios-build-artifact` + `open-sim` skill 把环境立起来再回来

## 调用契约（caller 怎么用）

skill 是**三段式契约**，第 2 段由 caller 自己驱动 —— 这样 caller 可以根据 spec 灵活组合任意点击/输入/手势，skill 不抢编排权：

```
┌────────────────────────────────────────────────────────────────┐
│ Step A: prepare   (skill 提供 shell)                            │
│   ─ 检查 ffmpeg / 选 device UDID / 建输出目录                   │
│   ─ 输出 RECORDING_PATH / FRAMES_DIR / DEVICE_UDID              │
├────────────────────────────────────────────────────────────────┤
│ Step B: record + act   (caller 驱动 — skill 给两套模板供选)     │
│   ─ 启动录屏 (mobile-mcp / xcrun simctl)                       │
│   ─ 把 app 走到动画起点 (caller 知道怎么走、本 skill 不管)      │
│   ─ 触发动画 (tap send / swipe up / type + enter / 等)         │
│   ─ 等动画跑完 + 一点 buffer (default +0.5s)                   │
│   ─ 停止录屏                                                    │
├────────────────────────────────────────────────────────────────┤
│ Step C: extract   (skill 提供 shell)                            │
│   ─ ffmpeg 抽 N 帧 → frames/frame-001.png ... frame-NNN.png     │
│   ─ 写 meta.json                                                │
│   ─ 报告给 agent: FRAMES_DIR + 帧文件清单                       │
└────────────────────────────────────────────────────────────────┘

Agent 拿到 FRAMES_DIR 后用 Read 工具看每一帧 (Claude 支持 PNG 多图输入)，
对照 spec 写「pass / fail + 哪一帧错」结论给主 agent。
```

### 入参（caller 准备好以下信息）

| 入参 | 是否必填 | 说明 |
| ---- | ---- | ---- |
| `WORKTREE_SLUG` | 必填 | 当前 worktree 名（caller 从主 agent 入参拿；executor 已经有），决定输出目录前缀。一般是 spec slug |
| `CASE_SLUG` | 必填 | 动画用例短名（小写 kebab-case，例 `chat-send-morph` / `dismiss-sheet`），决定 frame 子目录 |
| `DEVICE_UDID` | 必填 | iOS Simulator UDID（caller 从 `xcrun simctl list devices booted` 或 `mobile_list_available_devices` 拿）。Android 用 `adb` device id |
| `EXPECTED_DURATION_SECONDS` | 选填，默认 3 | 估计动画时长（含起手 + 动画 + 收尾）。caller 按 spec 估；偏长无所谓、ffmpeg 会全程抽帧 |
| `FRAME_COUNT` | 选填，默认 10 | 抽几帧。短动画（<1s）建议 6-8、长动画（>2s）建议 10-15 |
| `BACKEND` | 选填，默认 `auto` | `auto` / `mobile-mcp` / `xcrun`。auto 优先 mobile-mcp，调失败退到 xcrun |
| `PLATFORM` | 选填，默认 `ios` | `ios` / `android`（android 走 adb screenrecord，详见 §Android 适配） |

### 出参（skill 在 Step A 末尾输出）

```
RECORDING_PATH=<绝对路径>   # caller Step B 启动录屏时写到这个 path
FRAMES_DIR=<绝对路径>       # frames 子目录，Step C 写完后给 agent
META_PATH=<绝对路径>        # meta.json，Step C 写元数据
DEVICE_UDID=<回显>          # 透传 caller 用
BACKEND_RESOLVED=<mobile-mcp|xcrun>  # auto 模式下报告实际选的后端
```

### 出参（Step C 末尾打印）

```
FRAMES_DIR=<绝对路径>
FRAMES=<8|10|N>            # 实际抽到几帧
RECORDING_DURATION_SECONDS=<float>
NEXT_STEPS_FOR_AGENT: 用 Read 工具逐帧看 frame-001 ... frame-NNN，对照 spec 写 pass/fail
```

## Step A: prepare

跑 `scripts/prepare.sh`，它会：检查 ffmpeg / 校验 device 状态 / 建好 `.reviews/ui-<slug>-<ts>/animation/<case-slug>/{frames,}` 目录 / 打印路径变量。

```bash
WORKTREE_SLUG=<slug> CASE_SLUG=<case> DEVICE_UDID=<udid> \
  EXPECTED_DURATION_SECONDS=<3> FRAME_COUNT=<10> PLATFORM=<ios|android> \
  bash ~/.claude/skills/record-ui-animation/scripts/prepare.sh
```

输出 `RECORDING_PATH=` / `FRAMES_DIR=` / `META_PATH=` 等 KEY=VALUE，caller `eval $(...)` 或自行 parse。目录约定 `.reviews/ui-<slug>-<ts>/animation/<case-slug>/` 与 executor 截图同 base —— `/ship` 流程的清理逻辑会覆盖到。

错误码见 `scripts/prepare.sh` 头注释（`ERR_FFMPEG_NOT_FOUND` / `ERR_SIM_NOT_BOOTED:<udid>` / `ERR_BAD_SLUG:<slug>` 等），全部 exit 1。

## Step B: record + act（caller 驱动）

skill 给两套模板。**caller 二选一**，根据自己 env：

### 模板 B1: mobile-mcp（推荐 — 在 executor / generator subagent 里）

caller 是 subagent 且有 `mcp__mobile-mcp__*` 工具访问权：

```
1. caller 调 mcp__mobile-mcp__mobile_start_screen_recording:
     device   = $DEVICE_UDID
     output   = $RECORDING_PATH
     timeLimit = $EXPECTED_DURATION_SECONDS + 2  ← 上限兜底，避免动作出错卡死

2. caller 把 app 走到动画起点（如果需要）：
     - mcp__mobile-mcp__mobile_launch_app / 已经在了就跳过
     - mcp__mobile-mcp__mobile_click_on_screen_at_coordinates / mobile_type_keys / mobile_swipe
     - 期间可以 mobile_take_screenshot 一张确认到位

3. caller 触发动画（关键动作）：
     - 例：点 send → mobile_click_on_screen_at_coordinates(x=355, y=820)

4. caller 等动画完成：
     - Bash: sleep $(echo "$EXPECTED_DURATION_SECONDS + 0.3" | bc)
     - 或者通过 mobile_list_elements_on_screen 检测到稳定态再停

5. caller 调 mcp__mobile-mcp__mobile_stop_screen_recording(device=$DEVICE_UDID)
     - 返回 {path, size, duration_seconds}，path 应等于 RECORDING_PATH
```

### 模板 B2: xcrun simctl（caller 是 Bash 自动化 / 没 mcp env）

skill 提供两段：`record-xcrun.sh` 起录 + 返回 PID，`stop-xcrun.sh` SIGINT 收尾 + 校验文件。

```bash
# 1. 起录（脚本后台 fork simctl + 等 0.4s first frame + 返回 REC_PID）
eval "$(DEVICE_UDID=$DEVICE_UDID RECORDING_PATH=$RECORDING_PATH \
  bash ~/.claude/skills/record-ui-animation/scripts/record-xcrun.sh)"

# 2. caller 自己触发动画 —— 任意方式：osascript 控 Simulator、跑 UI test、纯 sleep（屏上动画自播）
sleep "$EXPECTED_DURATION_SECONDS"

# 3. 收尾（SIGINT + wait + 校验 mp4 是否完整）
REC_PID=$REC_PID RECORDING_PATH=$RECORDING_PATH \
  bash ~/.claude/skills/record-ui-animation/scripts/stop-xcrun.sh
```

### 不在本 skill scope

- 怎么点 send / 走到聊天页 / 触发哪个手势 → caller 看 spec 自己决定
- mocked vs real data → caller 准备
- 多个动作组合（点击 → 等 → 滑动）→ caller 写脚本

## Step C: extract

跑 `scripts/extract.sh`，它会：ffprobe 拿时长 → ffmpeg 等距抽 N 帧（默认 0.5x scale）→ 写 `meta.json` → 打印实际帧数。

```bash
RECORDING_PATH=$RECORDING_PATH FRAMES_DIR=$FRAMES_DIR META_PATH=$META_PATH \
  FRAME_COUNT=10 SCALE=0.5 \
  bash ~/.claude/skills/record-ui-animation/scripts/extract.sh
```

输出 `FRAMES_DIR=` / `FRAMES=<实际数>` / `RECORDING_DURATION_SECONDS=` / `META_PATH=`。

**为什么默认 scale 0.5**：Simulator @3x 录屏（iPhone 16 Pro 1206×2622），每帧 PNG 2-3MB。10 帧 = 20-30MB 进 agent context 会撑爆；0.5x 后 ≈600×1311、~700KB / 帧，10 张 ~7MB，agent 能全 Read。

## Android 适配（简略）

`PLATFORM=android` 时改两点：

- Step A 的 device 检查改 `adb -s $DEVICE_UDID get-state`，期望 `device`
- Step B 模板换成 `adb -s $DEVICE_UDID shell screenrecord /sdcard/recording.mp4 --time-limit N`、停录后 `adb pull`

Step C 完全一致（mp4 输入 ffmpeg 无差异）。

## 失败处理

| 错误码 | 意思 | caller 怎么办 |
|---|---|---|
| `ERR_FFMPEG_NOT_FOUND` | ffmpeg 没装 | `brew install ffmpeg`；不要自动装、要用户授权 |
| `ERR_SIM_NOT_BOOTED` | UDID 状态非 Booted | caller 先 `xcrun simctl boot` 或 `Skill(open-sim)` |
| `ERR_SIMCTL_DIED_EARLY` | recordVideo 进程刚起就退出 | 看 `REC_LOG` 文件诊断。最常见原因：`Host recording is already in progress` —— simulator 内部 recording 状态没释放（通常因为上次 simctl 进程被 SIGKILL / 异常退出、没收到 SIGINT finalize）。**清理方法**：`xcrun simctl shutdown $UDID && xcrun simctl boot $UDID`。这是为什么 `stop-xcrun.sh` 必须用 SIGINT —— SIGTERM/SIGKILL 会留下死状态污染下一轮录屏 |
| `ERR_RECORDING_MISSING` | mp4 没出文件 | stop 后 fd 关了但文件没 finalize；重跑；连续 2 次降级 |
| `ERR_RECORDING_TOO_SMALL` | mp4 <1KB | 录屏在第一帧前就被打断；caller 加 `sleep 0.6` 等 first frame |
| `ERR_FFPROBE_NO_DURATION` / `ERR_RECORDING_TOO_SHORT` | mp4 损坏 / 时长 <0.1s | 同 too small，重跑；caller 延长 sleep |

**两次失败后 caller 应当降级**为 `ui_dynamic_cases_skipped` 报给用户（恢复原 executor 路径），不要让动画验证阻塞整个 PASS / FAIL。

## 不做的事

- ❌ 不点击 / 不输入 / 不手势 —— caller 的事
- ❌ 不判断动画对不对 —— caller / 上游 agent 看完帧自己判
- ❌ 不出 GIF（Claude 不支持 GIF 输入、出了也只能给用户看，不在本 skill 责任范围；如果 caller 要给用户存档可以自己额外跑 `ffmpeg -i recording.mp4 -vf fps=10,scale=480:-1 -loop 0 output.gif`）
- ❌ 不自动 boot simulator / 不装 app —— 走 `find-ios-build-artifact` + `open-sim` 配套
- ❌ 不跨 device 并行录屏 —— 一个 caller 一段录屏（caller 想并行就用不同 CASE_SLUG 各跑一遍）
- ❌ 不改 simulator 设置 / 不改 status bar —— 录屏前现状即是现状
