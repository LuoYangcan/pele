---
name: open-sim
description: Build the iOS app, then install + launch it on this worktree's Simulator and bring the window to front. Use when the user asks to "打开模拟器", "open simulator", "跑模拟器", "在模拟器看效果", "编译跑一下", "build 跑模拟器", "launch on simulator". Skip for macOS app; for a real iPhone use the `run-device` skill instead.
---

# open-sim

「编译 → 装 → 启动 → 把 Simulator 窗口推到前台」一把梭。机械部分下沉在共享脚本 `~/.claude/scripts/run-ios.sh`（`--target sim`），本 skill 只负责调它 + 把结果转述给用户。真机版是 `run-device`（`--target device`），共用同一个脚本。

## 适用场景

- 刚改完 iOS 代码、想立刻 build + 在模拟器看效果
- 想从命令行 build + 启动 app 而不打开 Xcode

不适用：macOS app · **真机（用 `run-device`）** · release / archive 产物。

## 前置假设

- cwd 在 iOS 仓库（含 worktree）里某层，向上能找到 `justfile`
- 项目用 `just build-ios` build iOS Simulator Debug
- worktree 场景：装到 per-worktree `sim-<slug>`；非 worktree：退回 booted / 最新可用 iPhone（脚本内部 fallback）

## 执行

默认每次 build（保证看到当前代码）：

```bash
bash ~/.claude/scripts/run-ios.sh --target sim
```

- 用户**显式**说「不用 build / 跳过编译 / 直接装已有产物」→ 加 `--no-build`：
  ```bash
  bash ~/.claude/scripts/run-ios.sh --target sim --no-build
  ```

脚本会 build → 定位产物（扫 `Build/Products/*-iphonesimulator/`，取最新的 `.app`；configuration 名由项目定义且会变，不写死 `Debug-`） → 从产物 `Info.plist` 读 bundle id → 经 `worktree-sim.sh ensure` 拿 per-worktree sim（非 worktree 自动 fallback）→ `simctl install` + `launch` → `open -a Simulator`，最后打印 `----- run-ios result -----` 结果块。

## 报告给用户

转述结果块里的：用的哪台 sim（`WHERE`）+ UDID + `BUNDLE_ID` + `PID`。任何步骤失败脚本会 `ERROR:` + 非零退出 —— **原样把错误报给用户，不要自动尝试别的方案**。

## 省 context（可选）

`just build-ios` 会吐几千行 xcodebuild 日志。想把它挡在主对话外：Claude 派 Haiku / Sonnet；Codex 派 `command-runner`（Luna low），角色未加载时用 Terra low。subagent 只跑命令并返回结果块，不判断代码质量。

## 失败处理（脚本退出码）

| 退出码 | 含义 | 怎么办 |
|---|---|---|
| 2 | build 失败 | 原样报 xcodebuild 错误，不继续 |
| 3 | 找不到 `.app` | 仅 `--no-build` 时可能；让用户去掉 `--no-build` 重跑 |
| 4 | install / launch 失败 / 没可用 iPhone sim | 多半 sim 环境问题；提示装 iOS runtime（Xcode > Settings > Platforms）|

## 不做的事

- ❌ 不跑 `just generate` · 不切 scheme · 不处理 macOS / 真机（真机走 `run-device`）
- ❌ 不在用户没显式要求时跳过 build（默认每次 build）
