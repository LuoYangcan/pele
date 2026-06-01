---
name: find-ios-build-artifact
description: Locate the just-built iOS Simulator `.app` bundle for a project + resolve the per-worktree Simulator UDID — output `APP_PATH` (absolute) + `BUNDLE_ID` + `SIMULATOR_UDID` so callers can `simctl install -d <udid>` / `simctl launch <udid>` / mobile-mcp tools (which take a `device` parameter). Walks up from cwd to find a `.xcworkspace`, runs `xcodebuild -showBuildSettings`, verifies the `.app` exists, then invokes `~/.claude/scripts/worktree-sim.sh ensure` to lazy-create + boot the worktree's dedicated sim. Use when an executor / open-sim / similar caller has just built iOS with `just build-ios` (or equivalent) and now needs the build artifact paths. Skip when the caller already knows all three values, when there's no `.xcworkspace` ancestor (project uses bare xcodeproj — caller must adapt), or when targeting macOS / device (this skill is iOS Simulator only).
---

# find-ios-build-artifact

跑完 iOS Simulator build 后，找到产物 `.app` 路径 + bundle id + **当前 worktree 绑定的 simulator UDID**。caller 拿这三个值给 `simctl install -d <udid> <app>` / `simctl launch <udid> <bundle>` / mobile-mcp 工具（`device: <udid>` 参数）。

并行 session 隔离：每个 worktree 用专属 sim（`sim-<slug>`），由 `~/.claude/scripts/worktree-sim.sh ensure` lazy 管理。两个 session 同时跑也不会抢同一台。

## 触发

caller SOP 里需要 `APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID` 三个值，且当前已经跑过 iOS Simulator build。常见场景：

- **executor**：spec 第 4 节有 iOS UI 改动专项 → Step 4.5.1 拿 build artifact 准备装启
- **open-sim** skill：用户说"打开模拟器" → Step 2 拿 build artifact 装启
- 任意 caller 想把已 build 的 iOS Simulator app 装到模拟器跑

## 不触发

- caller 已经从主 agent / 上一步拿到 `APP_PATH` + `BUNDLE_ID`
- 项目没有 `.xcworkspace`（裸 `.xcodeproj` 或 SPM-only）—— 本 skill 用 workspace 路径假设，caller 需要自己适配
- 跑 macOS / device build（本 skill 假设 destination = `generic/platform=iOS Simulator`）
- 还没跑过 build —— `xcodebuild -showBuildSettings` 在没 build 时也能跑，但 `.app` 实际不存在；本 skill 会报 `BUILD_ARTIFACT_NOT_FOUND` 让 caller 决定下一步

## 执行步骤

### Step 1: 定位 workspace

从 cwd 向上找 `.xcworkspace` 文件夹（很多项目把它放在仓库根，但 monorepo 可能在子目录）：

```bash
WORKSPACE_DIR="$(pwd)"
WORKSPACE_NAME=""
while [[ "$WORKSPACE_DIR" != "/" ]]; do
  # 找当前目录下任一 .xcworkspace
  found=$(find "$WORKSPACE_DIR" -maxdepth 1 -name '*.xcworkspace' -type d 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    WORKSPACE_NAME="$(basename "$found")"
    break
  fi
  WORKSPACE_DIR="$(dirname "$WORKSPACE_DIR")"
done
[[ -n "$WORKSPACE_NAME" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: 找不到 .xcworkspace 祖先"; exit 1; }
```

### Step 2: 确定 scheme

caller 应该传入 scheme 名（例：`<YourApp>iOS` / `MyAppiOS`）。如果没传：

```bash
# 列 workspace 全部 scheme，让 caller 自己挑
xcrun xcodebuild -workspace "$WORKSPACE_DIR/$WORKSPACE_NAME" -list 2>/dev/null | sed -n '/Schemes:/,$p'
```

挑选启发式（caller 没指定时）：

- 项目根有 `AGENTS.md` / `Justfile` 提到主 scheme → 用它
- scheme 名字含 `iOS` / `iphone` 关键字优先
- 否则取列表第一条，并在输出里标注「scheme 自动选取，可能不准」

### Step 3: 拿 build settings

```bash
SETTINGS=$(cd "$WORKSPACE_DIR" && xcodebuild -workspace "$WORKSPACE_NAME" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null)
```

提取 3 个字段：

```bash
BUILT_DIR=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR =/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME =/ {print $2; exit}')
BUNDLE_ID=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER =/ {print $2; exit}')
APP_PATH="$BUILT_DIR/$APP_NAME"
```

### Step 4: 验证 `.app` 实际存在

```bash
[[ -d "$APP_PATH" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: $APP_PATH 不存在 — 先跑 just build-ios / Xcode build / xcodebuild build"; exit 1; }
```

`-showBuildSettings` 会**返回路径**即使还没 build，`.app` 实际不存在。验证一下避免 caller 拿到不存在的路径继续 `simctl install` 报错。

### Step 5: 拿 per-worktree simulator UDID

仅当 cwd 在 `.worktrees/<slug>/`（含 sub-worktree）内时跑。主仓库 / 非 worktree cwd 跳过本 step、`SIMULATOR_UDID` 输出空。

```bash
SIM_OUT=$(bash ~/.claude/scripts/worktree-sim.sh ensure 2>&1) && {
  SIMULATOR_UDID=$(echo "$SIM_OUT" | awk -F= '/^SIMULATOR_UDID=/ {print $2}')
} || {
  # 不在 worktree（exit 1）/ 没 .xcworkspace（exit 2）→ 不致命，留空让 caller 走 fallback
  # simctl 失败（exit 3）→ 同上、caller 自检环境
  SIMULATOR_UDID=""
}
```

#### 可选：指定 runtime 创建额外 sim

`worktree-sim.sh ensure` 支持可选 `--runtime <id>` 参数，创建一台**额外**绑定指定 runtime 的 sim（不替换默认 `sim-<slug>`），UDID 存 `.claude/sim-udid-<runtime-suffix>`。典型用法：

```bash
# 创建并 boot 一台 iOS 18.6 sim（除 sim-<slug> 之外的并存 sim）
bash ~/.claude/scripts/worktree-sim.sh ensure --runtime iOS-18-6
# → sim-<slug>-ios18-6，UDID 存 .claude/sim-udid-ios18-6
```

无参调用保持 backward compat（默认选最新 runtime）。`--runtime` 边界（不兼容 device type 兜底 / runtime 未安装报错 / shutdown/delete 联动）详见 `~/.claude/scripts/worktree-sim.sh` 头部注释。

### Step 6: 输出

caller 用 `eval` 或 source 拿四个变量；或者本 skill 直接打印 KEY=VALUE 让 caller parse：

```bash
echo "APP_PATH=$APP_PATH"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "SIMULATOR_UDID=$SIMULATOR_UDID"   # 可能为空（cwd 不在 worktree / 非 iOS 项目 / simctl 失败）
echo "WORKSPACE=$WORKSPACE_DIR/$WORKSPACE_NAME"
echo "SCHEME=$SCHEME"
```

## 错误处理

| 失败 | 错误码 | caller 怎么办 |
|---|---|---|
| 找不到 `.xcworkspace` 祖先 | `BUILD_ARTIFACT_NOT_FOUND: 找不到 .xcworkspace 祖先` | caller 自检 cwd 是不是在仓库内；裸 xcodeproj / SPM-only 项目改用其他方式 |
| `-showBuildSettings` 返回空 / 字段缺失 | `BUILD_ARTIFACT_NOT_FOUND: 无法解析 build settings` | 多半是 scheme 名错；caller 用 `xcodebuild -list` 核对 |
| `.app` 不存在 | `BUILD_ARTIFACT_NOT_FOUND: <path> 不存在` | 提示用户先跑 build；executor 应降级 `ui_verified: degraded` + `ui_degradation_reason: build_artifact_not_found` |
| `SIMULATOR_UDID` 为空且 caller 跑在 worktree 内 | 不在结构化输出报错，只在 stderr 留 WARN | review-mobile-ui 等 caller 自检 cwd / 落到旧的「booted 数量判断」fallback |

**不要**自己跑 `xcodebuild build` 去补 —— build 是 caller / 用户的责任，本 skill 只定位产物。
**不要**自己 boot / install / launch app —— 本 skill 只 ensure sim 存在 + booted，装启由 caller 拿 `SIMULATOR_UDID` 后跑。

## Caller 集成示例

### Executor 4.5.1（iOS UI 改动专项）

```
Skill(find-ios-build-artifact)   # 入参：scheme = <YourApp>iOS
# 输出：APP_PATH=/path/to/<YourApp>.app, BUNDLE_ID=<your.bundle.id>, SIMULATOR_UDID=A1B2-...

# build artifact 失败 → 标 ui_verified: degraded + reason: build_artifact_not_found
# SIMULATOR_UDID 空（非 worktree / simctl 失败）→ 走 review-mobile-ui Step 2 fallback
# 成功 → simctl install -d $SIMULATOR_UDID $APP_PATH; simctl launch $SIMULATOR_UDID $BUNDLE_ID
```

### open-sim skill Step 2

```
Skill(find-ios-build-artifact)   # 入参：scheme = <YourApp>iOS
# 失败 → 提示用户 "先跑 just build-ios"
# 成功 → Step 3 用 $SIMULATOR_UDID 装启（不再让用户挑 sim — worktree 已绑定）
```

## 不做的事

- ❌ **不跑 build** —— 没 build / 产物不存在时只报错，让 caller 决定下一步
- ❌ **不自动猜 scheme** —— caller 必须传或本 skill 列 scheme 让 caller 挑
- ❌ **不处理 macOS / device** —— destination 写死 `generic/platform=iOS Simulator`
- ❌ **不装 app / 不启 app** —— 那是 caller 的事（`simctl install/launch` 或 mcp tool）
- ❌ **不让 caller 自选 simulator** —— per-worktree UDID 由 `worktree-sim.sh ensure` 唯一决定，caller 不另选

## Why（核心）

- 三字段（`APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID`）打包输出 — caller 一次拿齐 install/launch 所需的全部
- `SIMULATOR_UDID` 来自 `worktree-sim.sh ensure`：lazy create + boot per-worktree `sim-<slug>`，并行 session 各自有 sim、mobile-mcp `device` 参数能精确路由
