---
name: review-mobile-ui
description: iOS / Android Simulator UI 验收 SOP 真相源。把 spec 第 4 节「iOS UI 改动专项」用例分静态 / 动态两档跑：静态用 mobile-mcp `list_elements_on_screen` + `save_screenshot` 单次采样判间距 / frame / 对齐；动态 invoke record-ui-animation skill 录屏抽帧 + Read 判动画。包含 build artifact 定位（invoke find-ios-build-artifact）、simulator 状态判断、mcp 调用预算、降级路径、结构化结论字段。由 ui-reviewer subagent 调用；generator 的 figma diff 自测不走本 skill（自检 vs 验收两条路径）。Skip when：spec §4 无 iOS UI 改动专项 / 非 iOS Simulator 目标（真机 / macOS / watchOS）/ caller 没拿到 build artifact 路径。
---

# review-mobile-ui

iOS UI 验收的 SOP 真相源。由 ui-reviewer subagent invoke 后按本文跑。本 skill **不**包含 shell 脚本——shell 能力借用 `record-ui-animation` skill（动态用例）和 `find-ios-build-artifact` skill（拿 .app 路径）。

## 触发

- spec 第 4 节有「iOS UI 改动专项」小节 + 至少 1 条 mobile-mcp 冒烟用例
- ui-reviewer subagent 被主 agent 调起（用户显式说"跑 UI 验收 / UI 走查 / review UI / 看下 UI"等关键词）

## 不触发

- spec §4 没 iOS UI 改动专项 → 直接返回 `ui_verified: not_applicable`
- 非 iOS Simulator（真机 / macOS app / watchOS / tvOS）→ 本 skill 不覆盖、返回 `degraded` + `reason: target_not_supported`
- generator 的 figma diff 自测——那是 generator 自检（Step 4.5），用 generator 自己的 mobile-mcp 工具，不走本 skill

## 工作流程（caller 按顺序跑）

### Step 1: 准备 build artifact

```
Skill(find-ios-build-artifact)   # 入参：scheme（项目主 iOS scheme，例 <YourApp>iOS）
# 输出：APP_PATH=<绝对路径>  BUNDLE_ID=<bundle id>
```

scheme 名从项目 AGENTS.md / Justfile 拿。

skill 报 `BUILD_ARTIFACT_NOT_FOUND` → 编译已通过但 .app 找不到，环境异常 → **降级**：返回 `ui_verified: degraded` + `ui_degradation_reason: build_artifact_not_found`，不判 FAIL。

### Step 2: 确认 simulator 状态

> ⚠️ **mobile-mcp 关键差异**：mobile-mcp **没有** `udid:` 参数路由到指定 sim — 它隐式用当前 booted device。多 booted 时不能保证选到目标 sim。

用 Bash 检查 booted simulator 数量：

```bash
BOOTED=$(xcrun simctl list devices booted -j | python3 -c "
import json,sys
data=json.load(sys.stdin)
booted=[]
for runtime, devs in data['devices'].items():
    if 'iOS' not in runtime: continue
    for d in devs:
        if d.get('state') == 'Booted' and 'iPhone' in d.get('name',''):
            booted.append(d['udid'])
print('\n'.join(booted))
")
COUNT=$(echo "$BOOTED" | grep -c .)
```

按 `$COUNT` 分支：

- **`COUNT == 1`** → 直接用。后续 mobile-mcp 工具调用不需要传 device 参数
- **`COUNT == 0`** → 起一台（iOS 版本最新、iPhone）：
  ```bash
  UDID=$(xcrun simctl list devices available -j | python3 -c "
  import json,sys,re
  data=json.load(sys.stdin)
  def ver(rt):
      m=re.search(r'iOS-(\d+)-(\d+)', rt)
      return (int(m.group(1)), int(m.group(2))) if m else (0,0)
  candidates=[]
  for runtime, devs in data['devices'].items():
      if 'iOS' not in runtime: continue
      for d in devs:
          if 'iPhone' in d.get('name',''):
              candidates.append((ver(runtime), d['udid']))
  candidates.sort(key=lambda x:(-x[0][0], -x[0][1]))
  print(candidates[0][1] if candidates else '')
  ")
  [[ -n "$UDID" ]] || { echo "NO_SIMULATOR_AVAILABLE"; exit 1; }
  xcrun simctl boot "$UDID"
  ```
  - `NO_SIMULATOR_AVAILABLE` → 降级：`ui_degradation_reason: no_simulator_available`
- **`COUNT >= 2`** → 降级：`ui_degradation_reason: multiple_booted_simulators_mobile_mcp_cannot_target`，建议用户 shutdown 多余 sim 只留一台

### Step 3: 装 + 启动 app

```
mcp__mobile-mcp__mobile_install_app   { appPath: <APP_PATH> }
mcp__mobile-mcp__mobile_launch_app    { packageName: <BUNDLE_ID> }
```

Bash 推 Simulator 窗口到前面：

```bash
open -a Simulator
```

任一步失败 → 降级：`ui_degradation_reason: install_or_launch_failed: <错误摘要>`。

> mobile-mcp 工具参数名（`appPath` / `packageName` / `bundleId` 等）按主流 mobile-mcp 接口习惯写，**实际以 MCP server 注入的工具 schema 为准**。第一次调用前 Read tool description 确认。

### Step 4: 准备截图目录

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
SHOT_DIR=".reviews/ui-${WORKTREE_SLUG}-${TS}"
mkdir -p "$SHOT_DIR/refs"
```

`WORKTREE_SLUG` 由 caller (ui-reviewer subagent) 在入参拿到。`.reviews/` 在 `.gitignore`、`/ship` 流程会清。`refs/` 子目录存 figma node 对照图（视觉层用）。

### Step 5: 跑每条冒烟用例

> ⚠️ **两条路径**：
>
> - **静态类**（间距 / frame / 布局）→ 5.b 路径，`mobile_list_elements_on_screen` + `mobile_save_screenshot` **单次采样**判断。**禁用**任何改 app 状态的工具（`type_keys` / `swipe` / `double_tap` / `long_press`）。mcp 在动态 UI 上 sample 不可靠。
> - **动态类**（动画 / 过渡 / 输入流 / 手势引起的状态变化）→ 5.c 路径，invoke `record-ui-animation` skill 录屏 + 自己 Read 帧序列判断。**仅在录屏窗口期间**允许 `type_keys` / `swipe` 触发动画——这是 5.c 的指定路径。

#### 5.a 用例分类（每条用例先判类型）

| 分类 | 关键词信号 | 处理 |
|---|---|---|
| **静态类** | 「间距」「padding」「margin」「对齐」「frame」「布局」「位置」「字号」「颜色」「在 <静态页> 看 X」 | 进 5.b |
| **动态类** | 「动画」「过渡」「弹出/收起」「展开/折叠」「输入后变化」「按下 X 后 Y 变 Z」「滑动到底部加载」「loading」「转场」「键盘弹起」「toast」「sheet present/dismiss」「飞行 / fly / morph / fade」 | 进 5.c |
| **不确定** | 描述含糊 | **默认按动态类处理**——宁可走 5.c 自验或降级让用户确认 |

#### 5.b 静态用例核对（每条硬预算）

| 步骤 | 上限 | 说明 |
|---|---|---|
| 导航 `mobile_click_on_screen_at_coordinates` | spec 最短路径所需次数（通常 0-3） | 仅到达目标页面，不 explore |
| 导航用 `mobile_list_elements_on_screen` | 配合 tap，最多 N 次 | 找 label / accessibility identifier 拿坐标；只用于导航 |
| 等待 UI 稳定 | 1 次 `sleep 1` | 让 layout settle |
| **核心采样 `mobile_list_elements_on_screen`** | **1 次** | 拿目标页面元素列表（坐标 / accessibility / label / frame）—— 文本层间距判定数据源 |
| **`mobile_save_screenshot`** | **1 次** | 落 `<SHOT_DIR>/case-<N>-static.png`，文本层 + 视觉层共享 |
| **`mcp__plugin_figma_figma__get_screenshot`** | **1 次**（仅 spec §4 参考稿列表命中本用例时） | 落 `<SHOT_DIR>/refs/case-<N>-figma.png`，视觉层对照图 |
| `mobile_take_screenshot` | **0 次** | `save_screenshot` 已覆盖；`take_screenshot` 会把图返给 LLM 烧 token |
| `mobile_type_keys` / `mobile_swipe_on_screen` / `mobile_double_tap_on_screen` / `mobile_long_press_*` | **0 次** | 改 app 状态，5.b 静态档位禁止 |

**判定**（文本层 + 视觉层并行；任一层产 issue 都进 issues 列表）：

**文本层**（不依赖 figma，必跑）：

- 元素 frame 字段（schema 因 mobile-mcp 版本而异，常见 `rect` / `frame` / `bounds` 含 x/y/width/height）算间距：`b.x - (a.x + a.width)` 之类
- 容差 **±2pt**
- 一致 → 文本层 PASS
- 不一致 → blocking issue（`issue_type: ui-frame-mismatch`、`file: <SHOT_DIR>/case-<N>-static.png`、测得 vs 期望差值）
- 元素列表返空 / 报错 → blocking issue（`issue_type: ui-crash`）

**视觉层**（仅 spec §4「参考稿列表」表有行命中本用例时跑；命中规则：行的「对应用例」列 == `case-<N>` 或 `*`）：

1. Read spec §4「对齐严格度」字段（`strict` / `loose`）
2. 调 `mcp__plugin_figma_figma__get_screenshot { fileKey, nodeId }`，存 `<SHOT_DIR>/refs/case-<N>-figma.png`
   - 拉图失败 → warning issue（`issue_type: ui-figma-mismatch`、`severity: warning`、`description: figma_screenshot_failed: <reason>`）；不 blocking、不影响本用例 verdict、跳过本用例视觉层
3. 拉到 → Read `case-<N>-figma.png` 和 `case-<N>-static.png` 进 context，按 spec §4「设计稿覆盖范围」字段逐项对比
   - `strict`：覆盖范围里任一项不符 → blocking issue（`issue_type: ui-figma-mismatch`、`severity: blocking`、`case_number: <N>`、`file: refs/case-<N>-figma.png vs case-<N>-static.png`、`description: <一句话差异点>`）
   - `loose`：仅判版式骨架对齐 + 颜色 token；不符 → warning issue（不 blocking）

**用例 verdict**：文本层 blocking ∪ 视觉层 blocking 任一 → 用例 FAIL；都无 blocking → 用例 PASS。

#### 5.c 动态用例：invoke record-ui-animation skill

每条动态用例 1 次 skill 调用、**不重跑**。

##### 5.c.1 调用

```bash
# A. 拿 booted sim UDID（Step 2 应该已经只剩一台 booted；这里再读一遍以防漂移）
UDID=$(xcrun simctl list devices booted -j | python3 -c "
import json,sys
d=json.load(sys.stdin)
for _,ds in d['devices'].items():
    for x in ds:
        if x['state']=='Booted' and 'iPhone' in x['name']:
            print(x['udid']); break")

# B. prepare
eval "$(WORKTREE_SLUG=$WORKTREE_SLUG CASE_SLUG=case-<N> DEVICE_UDID=$UDID \
  EXPECTED_DURATION_SECONDS=3 FRAME_COUNT=8 \
  bash ~/.claude/skills/record-ui-animation/scripts/prepare.sh)"

# C. 起录
eval "$(DEVICE_UDID=$UDID RECORDING_PATH=$RECORDING_PATH \
  bash ~/.claude/skills/record-ui-animation/scripts/record-xcrun.sh)"
```

**D. 触发动画**（按 spec 描述，仅本步允许 5.b 禁用工具）：

- spec 说「点 send 看 morph 飞向 chat」→ `mobile_list_elements_on_screen` 拿 send 坐标 → `mobile_click_on_screen_at_coordinates` 点
- spec 说「输入文本后输入框抖动」→ `mobile_type_keys`
- spec 说「上滑 sheet 看 dismiss」→ `mobile_swipe_on_screen`
- 仅触发**一次**——不要"多录几遍取平均"

**E.** `sleep <EXPECTED_DURATION_SECONDS + 0.5>` 等动画 + buffer。

**F. 收尾 + 抽帧**：

```bash
REC_PID=$REC_PID RECORDING_PATH=$RECORDING_PATH \
  bash ~/.claude/skills/record-ui-animation/scripts/stop-xcrun.sh

RECORDING_PATH=$RECORDING_PATH FRAMES_DIR=$FRAMES_DIR META_PATH=$META_PATH \
  FRAME_COUNT=8 \
  bash ~/.claude/skills/record-ui-animation/scripts/extract.sh
```

**G. Read 每一帧 PNG**（`$FRAMES_DIR/frame-001.png` ... `frame-008.png`），对照 spec：起手帧 / 中段帧 / 收尾帧的视觉是否符合预期、动画曲线是否合理、有无穿帮 / 错位 / 闪烁。

##### 5.c.2 判定 + 输出

```yaml
ui_dynamic_cases_verified:
  - case_number: <N>
    spec_description: <用例原文>
    frames_dir: <绝对路径>
    verdict: pass | fail
    observations: <一句话，例：「frame-001 send 按钮静止 → frame-004 文本气泡从 composer 起飞、缩放收缩 → frame-007 落到 chat 列表底部，曲线 ease-out 符合 spec」>
```

- `verdict: pass` → 不算 blocking
- `verdict: fail` → blocking issue（`issue_type: ui-animation-mismatch`、`case_number: <N>`、`frames_dir: <路径>`、`observation: <差异点>`），整体 verdict FAIL

##### 5.c.3 降级触发（任一即把本用例改写到 ui_dynamic_cases_skipped）

- `prepare.sh` / `record-xcrun.sh` / `stop-xcrun.sh` / `extract.sh` 任一报错
- 抽帧数 <2 （屏幕没动 / 触发没生效——simctl recordVideo 是 frame-driven）
- Read 完所有帧仍无法对照 spec 判断（关键帧缺失 / 视觉模糊 / spec 描述太抽象）

降级时本用例从 `ui_dynamic_cases_verified` 拿走 → 进 `ui_dynamic_cases_skipped` + `degradation_reason`。

**不重跑**——skill 失败两次以上的兜底逻辑在 skill 本身；本 SOP 这一层只跑 1 次、失败立即降级。

##### 5.c.4 不跑 install / launch

录屏期间 app 已经在 Step 3 的 session 里跑着——不要 terminate / 重启 / 重装。需要特定起点页面就用 `mobile_click_on_screen_at_coordinates` 导航过去再起录。**导航点击不算触发**：先导航到位 → `sleep 0.5` 等 layout settle → 再 prepare.sh / record-xcrun.sh。

#### 5.d 单 Session 复用 install / launch

整个 Step 5 内**只 install + launch 一次**——多条用例共享同一 app session。每条跑完**不要** terminate / 重启；用 `mobile_click_on_screen_at_coordinates` 导航到下一条用例所需页面。两条用例的页面互相不可达（一个在 OnBoarding、一个在主 tab） → 第二条标 `ui_verified: degraded` + `ui_degradation_reason: cross_flow_navigation_required`。

### Step 6: 汇总结论

按下表定 `ui_verified` 和 `ui_smoke_required`：

| 情况 | `ui_verified` | `ui_smoke_required` |
|---|---|---|
| 所有静态用例（文本层 + 视觉层）全 PASS + 动态 record skill 自验全 pass | `pass` | `false` |
| 所有静态用例全 PASS + 动态部分 skill 自验 / 部分降级 | `pass` | **`true`** |
| 所有静态用例全 PASS + 没有动态用例 | `pass` | `false` |
| 所有静态用例全 PASS + 动态全降级 | `pass` | **`true`** |
| 任一静态用例 FAIL（文本层 frame 不符 / 视觉层 `strict` diff 不符 / `ui-crash`）或动态 skill 自验 verdict=fail | `fail` | `true` |
| 全部用例都是动态 + skill 全部失败降级 | `degraded` | `true` |
| 视觉层所有命中用例的 figma 拉图全部失败 | `degraded` | `true`（`ui_degradation_reason: figma_screenshot_all_failed`） |
| environment 问题（build artifact / simulator / install/launch 失败） | `degraded` | `true` |

**figma 拉图副作用**：视觉层 `get_screenshot` 单条失败（非全部）→ warning issue，不阻断 verdict，但 `ui_smoke_required` 升级为 `true`。

输出字段：

- `ui_static_cases_passed`: list of case numbers，仅 `ui_verified ∈ {pass, fail}` 时给
- `ui_dynamic_cases_verified`: list of `{case_number, spec_description, frames_dir, verdict, observations}`
- `ui_dynamic_cases_skipped`: list of `{case_number, spec_description, degradation_reason}`
- `ui_screenshots_dir`: 仅 `ui_verified ∈ {pass, fail}` 时给（动态降级 / environment 降级时**没有**截图产出）
- `ui_degradation_reason`: 仅 `ui_verified == degraded` 时给（`build_artifact_not_found` / `no_simulator_available` / `multiple_booted_simulators_mobile_mcp_cannot_target` / `install_or_launch_failed: <details>` / `target_not_supported` / `all_cases_dynamic` / `cross_flow_navigation_required` / `figma_screenshot_all_failed`）

## 禁止

- ❌ **超出 5.b 单条静态用例的 mcp 调用预算**——每条静态用例 1 次 `mobile_list_elements_on_screen`（核心采样）+ 1 次 `mobile_save_screenshot` + 必要导航
- ❌ **用 5.b 静态 sample 路径验证动画**——容易抓中间帧、还吃调用次数。动态**只走 5.c**；skill 失败再降级到 `ui_dynamic_cases_skipped`
- ❌ **5.b 静态用例期间** `mobile_type_keys` / `mobile_swipe_on_screen` / `mobile_double_tap_on_screen` / `mobile_long_press_*`——会触发动态 UI / 改 app 状态。5.c record skill 路径下允许这些工具仅用于触发动画（且仅在 `record-xcrun.sh` 起录 → `stop-xcrun.sh` 收尾的窗口内）
- ❌ **`mobile_uninstall_app` / `mobile_terminate_app`**：Session 内只 install + launch 一次（5.d）
- ❌ 同一条静态用例多次 `mobile_list_elements_on_screen` / `mobile_save_screenshot`：1+1 已经够判间距；觉得不够说明 spec 用例本身该拆或本来就不该归静态
- ❌ 「探索式」验收：不主动到处点 / 滚列表 / 测 spec 没列的 corner case——验收只回答 spec 问的问题
- ❌ 用 mobile-mcp 改 simulator 上别的 app 的状态（删数据 / 改设置 / 关 app）

## Why（核心）

- 静态 vs 动态分类：mobile-mcp 在动态 UI 上 sample 会抓到中间帧，间距 / frame 不对
- 5.b 1+1 预算：核心采样 1 次足够；多次 sample 不增加准确性反而推高 mcp 调用 + token
- 5.c 走录屏：动画看时序，单帧 sample 失去时序信息
- 降级路径而非硬失败：environment 问题（build artifact / simulator / 多 booted / 跨流程导航）不是 generator 的代码问题
- 不重跑动态用例：record skill 失败兜底在 skill 内；本 SOP 单次失败立即降级
- 截图存到 `.reviews/`：spec 不被污染，`.gitignore` 已排除
