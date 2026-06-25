---
name: run-device
description: Build the iOS app for a connected real iPhone (`<IOS_BUILD_DESTINATION>` device build), then install + launch it via `devicectl`. Use when the user asks to "装真机", "真机跑一眼", "install on device", "run on device / on my iPhone", "部署到手机", "真机调试", "put it on my phone". Auto-picks the single paired device; with >1 paired you pass the device id. Skip for the simulator (use `open-sim`), macOS, or release / archive.
---

# run-device

把当前 iOS 代码 build + 装 + 起到**连着的真机**上。机械部分下沉在共享脚本 `~/.claude/scripts/run-ios.sh`（`--target device`，跟 `open-sim` 共用），本 skill 只调它 + 转述结果。

## 适用场景

- 想在真实硬件上跑一眼（runtime 信心：能编译 / 安装 / 启动、资源链路没坏）
- 真机调试某个只在设备上复现的行为

不适用：模拟器（用 `open-sim`）· macOS · release / archive。

## 前置假设（真机特有）

- iPhone **插上线 + 解锁 + 已信任此电脑**，且 paired（`xcrun devicectl list devices` 能看到）
- 签名已在仓库 `Local.xcconfig` 配好（`DEVELOPMENT_TEAM` + Automatic），真机 build 不用额外配置
- cwd 在 iOS 仓库（含 worktree）里某层，向上能找到 `justfile`

## 执行

```bash
bash ~/.claude/scripts/run-ios.sh --target device
```

脚本会：自动选**唯一 paired 设备**的 CoreDevice `identifier`（`devicectl list devices` 的 `identifier` UUID，如 `A1B2C3D4-...`）→ `<IOS_BUILD_DESTINATION>="platform=iOS,id=<id>" just build-ios` → 定位 `Debug-iphoneos/*.app` → 从产物 `Info.plist` 读 bundle id → `devicectl device install app` + `process launch` → 打印 `----- run-ios result -----` 结果块。

- 接了**多台** paired 设备 → 脚本报错列出候选，让用户挑，再传 id：
  ```bash
  bash ~/.claude/scripts/run-ios.sh --target device --device-id <identifier>
  ```
- 已 build 过、只想重装 → 加 `--no-build`。

## 报告给用户

转述结果块：装到哪台（`WHERE=device:<name>`）+ `UDID`（= CoreDevice identifier）+ `BUNDLE_ID` + `PID`。任何步骤失败脚本会 `ERROR:` + 非零退出 —— **原样报给用户，不要自动换方案**。

## 省 context（可选）

真机 build 比 sim 慢、xcodebuild 日志更长。想挡在主对话外：派一个 `model: haiku` / sonnet 的 subagent 跑这条命令、只回结果块。skill 本身 model-agnostic，派不派是调用时决定。

## 失败处理（脚本退出码）

| 退出码 | 含义 | 怎么办 |
|---|---|---|
| 1 | 没 paired 设备 / 多台需指定 / `devicectl` 没就绪 | 让用户插线+解锁+信任，或按提示传 `--device-id` |
| 2 | 真机 build 失败 | 多半设备没连好 / 锁屏 / 没信任 / 签名问题；原样报 xcodebuild 错误 |
| 3 | 找不到 `.app` | 仅 `--no-build` 时可能；让用户去掉 `--no-build` 重跑 |
| 4 | devicectl install / launch 失败 | 设备插着+解锁+信任？install 成功 launch 才有意义 |

设备 `tunnelState` 不是 `connected`（拔线 / 锁屏 / 没开 dev session）时脚本会先 `WARN:` 但仍尝试，让真实的 xcodebuild / devicectl 错误兜底。

## 不做的事

- ❌ 不跑 `just generate` · 不切 scheme · 不碰模拟器（sim 走 `open-sim`）
- ❌ 不配签名 / 不处理 provisioning（假设 `Local.xcconfig` 已就绪）
- ❌ 不在用户没显式要求时跳过 build（默认每次 build）
