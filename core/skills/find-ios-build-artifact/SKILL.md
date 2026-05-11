---
name: find-ios-build-artifact
description: Locate the just-built iOS Simulator `.app` bundle for a project — output `APP_PATH` (absolute) + `BUNDLE_ID` so callers can `simctl install` / `simctl launch` / mcp install_app+launch_app. Walks up from cwd to find a `.xcworkspace`, runs `xcodebuild -showBuildSettings` to read `BUILT_PRODUCTS_DIR / FULL_PRODUCT_NAME / PRODUCT_BUNDLE_IDENTIFIER`, then verifies the `.app` exists. Use when an executor / open-sim / similar caller has just built iOS with the project's `<your iOS build recipe>` (e.g. `just build-ios`, `xcodebuild ... build`, or a project-specific script) and now needs the build artifact paths. Skip when the caller already knows `APP_PATH` and `BUNDLE_ID`, when there's no `.xcworkspace` ancestor (project uses bare xcodeproj — caller must adapt), or when targeting macOS / device (this skill is iOS Simulator only).
---

# find-ios-build-artifact

跑完 iOS Simulator build 后，找到产物 `.app` 路径 + bundle id。这是 executor 跑 UI 冒烟、open-sim skill 装启 app 等场景的共用前置步骤——本 skill 把那段 `xcodebuild -showBuildSettings` 提取逻辑抽出来，让 caller 一行 invoke 拿到结构化输出。

## 触发

caller SOP 里需要 `APP_PATH`（绝对路径）+ `BUNDLE_ID` 两个值，且当前已经跑过 iOS Simulator build。常见场景：

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

caller 应该传入 scheme 名（如项目 `<YourApp>iOS` / `AcmeiOS` 等）。如果没传：

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
[[ -d "$APP_PATH" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: $APP_PATH 不存在 — 先跑 <your iOS build recipe>（如 just build-ios / Xcode build / xcodebuild build）"; exit 1; }
```

`-showBuildSettings` 会**返回路径**即使还没 build，`.app` 实际不存在。验证一下避免 caller 拿到不存在的路径继续 `simctl install` 报错。

### Step 5: 输出

caller 用 `eval` 或 source 拿三个变量；或者本 skill 直接打印 KEY=VALUE 让 caller parse：

```bash
echo "APP_PATH=$APP_PATH"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "WORKSPACE=$WORKSPACE_DIR/$WORKSPACE_NAME"
echo "SCHEME=$SCHEME"
```

## 错误处理

| 失败 | 错误码 | caller 怎么办 |
|---|---|---|
| 找不到 `.xcworkspace` 祖先 | `BUILD_ARTIFACT_NOT_FOUND: 找不到 .xcworkspace 祖先` | caller 自检 cwd 是不是在仓库内；裸 xcodeproj / SPM-only 项目改用其他方式 |
| `-showBuildSettings` 返回空 / 字段缺失 | `BUILD_ARTIFACT_NOT_FOUND: 无法解析 build settings` | 多半是 scheme 名错；caller 用 `xcodebuild -list` 核对 |
| `.app` 不存在 | `BUILD_ARTIFACT_NOT_FOUND: <path> 不存在` | 提示用户先跑 build；executor 应降级 `ui_verified: degraded` + `ui_degradation_reason: build_artifact_not_found` |

**不要**自己跑 `xcodebuild build` 去补 —— build 是 caller / 用户的责任，本 skill 只定位产物。

## Caller 集成示例

### Executor 4.5.1（iOS UI 改动专项）

```
Skill(find-ios-build-artifact)   # 入参：scheme = <YourApp>iOS
# 输出：APP_PATH=/abs/path/to/<YourApp>.app, BUNDLE_ID=com.example.<yourapp>

# 失败 → 标 ui_verified: degraded + reason: build_artifact_not_found，不判 FAIL
# 成功 → 进 4.5.2 拿 simulator UDID
```

### open-sim skill Step 2

```
Skill(find-ios-build-artifact)   # 入参：scheme = <YourApp>iOS
# 失败 → 提示用户 "先跑 <your iOS build recipe>"
# 成功 → 进 Step 3 选模拟器、装启
```

## 不做的事

- ❌ **不跑 build** —— 没 build / 产物不存在时只报错，让 caller 决定下一步
- ❌ **不自动猜 scheme** —— caller 必须传或本 skill 列 scheme 让 caller 挑
- ❌ **不处理 macOS / device** —— destination 写死 `generic/platform=iOS Simulator`
- ❌ **不装 app / 不启 app** —— 那是 caller 的事（`simctl install/launch` 或 mcp tool）
- ❌ **不挑 simulator UDID** —— 那也是 caller 的事

## Why

`xcodebuild -showBuildSettings` 三字段提取这段 shell 同时存在于：

1. `~/.claude/agents/executor.md` Step 4.5.1（24 行）
2. `<project>/.claude/skills/open-sim/SKILL.md` Step 2（10 行）

两处复制粘贴 = 同一段 shell 维护两份。某天 Apple 改了 setting 字段名（例：未来某个 Xcode 把 `FULL_PRODUCT_NAME` 改成别的），两份要同时改、否则 executor 跟 open-sim 一边能跑一边不行。抽出来一处维护：

- 任何 caller `Skill(find-ios-build-artifact)` 拿一致输出
- 错误码 / 报错信息一致 → caller 路由逻辑（degraded / 报用户 / 直接失败）也一致
- 项目里**新加** caller（例：将来想从 macOS connector 装 iOS app 跑某个 e2e flow）可以直接 invoke，不必抄一遍 shell
