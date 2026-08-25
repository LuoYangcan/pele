---
name: figma-asset-export
description: 从 Figma 切图（导出图标 / 插画 / logo 资源）进 iOS 工程的规范——该切图还是用设计系统 / SF Symbol 还原的决策、切图格式选型、别从几何重画。Use when：从 figma 切图 / 导出自定义图标 / 插画 / logo 进 iOS、决定切图还是还原、定切图格式、排查「图标资源渲染偏色 / 偏大 / 糊」。Skip when：本次没有自定义资源（图标全走设计系统 / SF Symbol）/ 非 iOS / 用户明确手动切图。
---

# figma-asset-export

从 Figma 切图进 iOS 的规范。figma MCP **能切图**：`get_design_context` 对含可导出资源的节点返回**资源下载 URL**（SVG / PNG）——这就是切图入口（`get_screenshot` 是整节点栅格、不是切图）。规范要点：先判**该不该切**，再定**格式**，最后**用导出文件、别从几何重画**。

## 触发 / 不触发

触发：

- 从 figma 切图 / 导出自定义图标 / 插画 / logo 进 iOS
- 决定某个图形该切图还是用设计系统 / SF Symbol 还原
- 定切图格式（矢量 vs @1x/@2x/@3x）
- 排查「切出来的资源渲染偏色 / 偏大 / 糊 / 对不齐」

不触发：

- 本次没有自定义资源（图标全走设计系统 / SF Symbol）
- 非 iOS
- 用户明确手动切图导出

## 第一步：该切图，还是用代码还原？

| 图形 | 处理 |
|---|---|
| 设计系统已有组件 / 能用 SF Symbol 表达 | **不切**——用组件 / SF Symbol（有 Code Connect 时解析到真实组件），尺寸 / 光学约定已编码进组件 |
| 纯单色简单形状（箭头 / 勾 / 加号等）能用 SF Symbol 近似 | 优先 SF Symbol；像素级要求时才切 |
| 自定义图标 / 插画 / logo / 多色图形 / 品牌资源 | **切图**——代码画不出、画出来也会漂 |

## 切图机制（怎么拿到文件）

1. `get_design_context({nodeId})` → 返回里含**资源下载 URL**（exportable 节点 / image fill 节点）。figma 给的是 **SVG / PNG** URL，**不直接给 PDF**（PDF 是 iOS 侧 SVG→PDF 转换）。
2. `curl -sL "<asset_url>" -o .specs/<slug>-assets/<语义名>.<svg|png>` 下载导出文件。
3. **导出 box = 外框、不是裁剪 path**：figma 图标常是固定外框裹更小字形 + 光学留白；导出要带外框留白（否则资源被裁到字形 bbox、渲染偏大 / 破对齐）。已知 MCP bug 会把 SVG 裁到 path bbox → 拿到后核对尺寸，必要时按 metadata 外框尺寸显式设 box。

## 第二步：格式选型（iOS）

| 资源类型 | figma 导出格式 | iOS 处理 |
|---|---|---|
| 单色、可缩放（多数图标） | **SVG**（figma 给 SVG，不给 PDF） | 进 asset catalog（Xcode 12+ 直接放 SVG，或 iOS 侧转 PDF），勾 **Preserve Vector Data** + **Single Scale**；render 设 **template**、用 `<DesignSystemPackage>` / Color token **tint**（**不烤死颜色**） |
| 多色矢量（插画 / 彩色 logo） | **SVG** | 同上但 render **original**（保留多色） |
| 位图 / 照片 / 复杂渐变 | **PNG** | `.imageset` 放 **@1x / @2x / @3x 各一份**（pt 尺寸 = @1x 那份），设备按 scale 自动选 |

- **单色图标必须 template + token tint**：和设计 token 名核对（走 figma-precise-extract 的 variable_defs），别硬编码十六进制——深色 / 多主题才不串色。
- iOS 18 SVG 直接进 asset catalog 也可；老工程惯例转 PDF。按项目现状走。

## 别从几何重画

拿到导出文件就**用它**，不要看 `get_design_context` 的 path data 自己在代码里重画 `Path` / 拼 shape。冻结 HTML（见 `figma-precise-extract`）里即使含 inline `<svg>` path，implementation owner 也不从它几何重画；图标只使用最终 plan 列出的导出资源。

## 在 plan-first delivery 里的位置

- **Root/source prep**：在 Default mode、源码写入前冻结导出资源到 `.specs/<slug>-assets/`，把格式、render mode 和 tint token 写入最终 plan 或 ExecPlan。切图与 measurement HTML 并列：前者给二进制资源，后者给布局测量。
- 把 file/node/version（可用时）与每个导出资源 SHA-256 纳入 design binding；无 immutable version 时只按冻结 bundle 验收，不在 review 期间重新下载 latest。
- 导出结果若引出新的行为、scope、架构或验收决策，Root 先回 DISCOVER/PLAN_READY 更新 authoritative plan，再继续实现。
- **implementation owner**：把冻结资源接入 asset catalog，设置 template/original、tint token 和 Preserve Vector Data；设计源变化时由 Root 重新冻结，不在实现中临时换资源。
- **ui-reviewer**：可运行 build PASS 后，对冻结 PNG 核对尺寸、颜色和清晰度。

## 硬约束

- ❌ 不用 `get_screenshot` 当切图（那是整节点栅格、不是资源文件）
- ❌ 不从 path 几何在代码里重画自定义图标 / 插画
- ❌ 单色图标不烤死十六进制颜色 —— template + token tint
- ❌ implementation worker 不重新切图；冻结资源和共享清单由 Root 管理
- ✅ 自定义资源走 `get_design_context` 资源 URL（figma 给 SVG / PNG）导出；导出 box = 外框
- ✅ 单色可缩放→SVG（Xcode 直接用或转 PDF）template + token tint；多色→original；位图→@1x/2x/3x

## Why（核心）

切图漂移两大根因是代码重画丢光学细节，以及导出裁到 glyph bbox 或烤死颜色。资源先冻结，implementation owner 只负责接入。
