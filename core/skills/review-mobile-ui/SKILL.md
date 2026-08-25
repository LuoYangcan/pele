---
name: review-mobile-ui
description: iOS Simulator UI 验收 SOP。由 ui-reviewer 在 Figma、动画、复杂 UI 或用户显式要求时，对已有可运行 build 执行静态截图和动态录屏核对。不负责 build 或源码修改。
---

# Mobile UI review

调用方必须提供最终 plan 中的明确用例、当前源码的 build 证据、冻结设计工件、绑定到实际 `.app`/环境的 `build=`，以及匹配这些输入的 `ui_review_input_fingerprint`。只回答这些用例，不做探索式测试；fingerprint 不匹配时返回 `NEEDS_INPUT`。

## 支持范围

- iOS Simulator：支持。
- Android、真机、macOS、watchOS、tvOS：本 skill 不覆盖，返回 `DEGRADED target_not_supported`。
- 缺少明确 UI 用例或设计依据：返回 `NEEDS_INPUT`。
- 缺少绝对 `APP_PATH`、app digest、bundle/scheme/config/destination 或指定 Simulator：返回 `NEEDS_INPUT build_identity_incomplete`；不要自行 build 或搜索其他产物。

## 1. 定位产物与 Simulator

只使用调用方绑定的 `APP_PATH`、`BUNDLE_ID`、scheme/config/destination 与 `SIMULATOR_UDID`。先用 `validation-receipt.sh --repo "$repo" artifact-digest "$APP_PATH"` 核对 digest，并用 `plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist"` 核对 bundle ID；不匹配返回 `NEEDS_INPUT build_identity_mismatch`。不得加载 `find-ios-build-artifact` 或改用“最近一次”产物。

指定产物或 Simulator 不存在时按环境限制降级。后续每个 `sim-use` 命令必须显式传 `--device "$SIMULATOR_UDID"`。

## 2. 安装与启动

整个 review session 只执行一次：

```bash
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
open -a Simulator
```

失败返回 `DEGRADED install_or_launch_failed`。不要重装、重启或切到另一台 Simulator 碰运气。

## 3. 证据目录

```bash
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="$repo/.reviews/ui-${WORKTREE_SLUG}-${timestamp}"
mkdir -p "$evidence_dir/refs"
```

## 4. 用例分类

| 类别 | 信号 | 路径 |
| --- | --- | --- |
| 静态 | frame、间距、对齐、版式、字号、颜色、圆角、静态状态 | 单次 AX 树 + 单次截图 |
| 动态 | 动画、转场、展开/收起、输入变化、loading、手势、键盘、toast、sheet | `record-ui-animation` |
| 不确定 | 用例描述不足以判断 | 动态路径；仍无法判断则 `NEEDS_INPUT` |

先按用例给出的最短路径导航到目标状态。只操作被测 app；不得改其他 app 或系统设置。

## 5. 静态用例

每条用例预算：必要导航、一次等待稳定、一次核心 `sim-use ui`、一次 `sim-use screenshot`。找不到稳定 accessibility selector 时才多读一次 AX 树定位；不要反复采样。

```bash
sim-use ui --device "$SIMULATOR_UDID"
sim-use screenshot --device "$SIMULATOR_UDID" \
  --output "$evidence_dir/case-<id>-static.png"
```

- 用 AX frame 计算尺寸/间距，默认容差 ±2pt；final plan 有其他容差时服从 plan。
- 有冻结 measurement HTML 时，以它为精确数值来源。
- 优先使用 `design=` 已绑定的冻结 reference；只有输入含 immutable provider version 且 live 结果可核对该 version 时，才获取一次 reference screenshot 到 `refs/`。
- `strict`：plan 覆盖范围内任一视觉偏差可 blocking；`loose`：只阻断版式骨架或 token 明显错误，细节记 warning。
- Figma 拉图单例失败记环境 warning；所有 reference 都失败且无法判断时 `DEGRADED figma_reference_unavailable`。

静态采样期间不使用 type、paste、swipe、long-press 或连续 tap 制造动态状态。

## 6. 动态用例

每条动态用例加载一次 `record-ui-animation`，按其 prepare → record → 触发 → stop → extract 流程执行。录屏窗口内才允许用 type/paste/swipe/gesture 等命令触发计划中的交互；每条只触发一次。

读取全部关键帧，检查起始、中间、结束状态、时序、错位、闪烁和计划要求。不要用单帧截图代替动画判断。

以下情况跳过该用例并记录环境限制，不盲目重录：录制/抽帧脚本失败、帧数少于 2、触发原语不可靠、关键帧不足以判断。若其余证据仍足够，整体可 PASS 并要求人工 smoke；全部动态用例均无法判断则 `DEGRADED`。

## 7. 汇总

- `PASS`：全部可判断用例通过；个别非关键环境缺口可列人工 smoke。
- `FAIL`：任一明确用例出现可复现的视觉、动画、交互或 crash 偏差。
- `DEGRADED`：环境使关键用例无法判断，不能归因于实现。
- `NEEDS_INPUT`：用例、预期或设计依据本身不足。

每条 case 返回 verdict、证据绝对路径和一句观察；FAIL issue 必须指向截图或 frames 目录。不要因为重试次数降低标准。

汇总前再次核对 app digest 和 UI context fingerprint，并用 `validation-receipt.sh --repo "$repo" artifact-digest "$evidence_dir"` 记录 evidence digest。输出实际 Simulator/runtime、locale、appearance 与 Dynamic Type；任一绑定输入在窗口内变化就丢弃结果。
