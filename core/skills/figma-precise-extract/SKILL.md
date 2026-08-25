---
name: figma-precise-extract
description: 从 Figma 设计稿提取 measurement-grade 精确尺寸、间距和 token。Use when：strict Figma→code 任务要冻结实现输入，或排查图标/间距偏差。Skip when：无 Figma 设计稿、非 UI 改动、用户选择 loose 严格度。
---

# figma-precise-extract

本 skill 把四个工具的输出烘焙成 measurement-grade 冻结 HTML：结构来自 `get_design_context`，精确数值来自 `get_metadata` 和 `get_variable_defs`，并按设计基准倍率换成 pt。implementation owner 读取冻结工件，不在写码时重新 live 取数。

## 触发 / 不触发

触发：

- strict Figma→code 任务在 Default mode 开始实现前冻结设计输入
- 任何 figma→code 任务要拿精确图标尺寸 / 间距 / token
- 排查「按 figma 实现但图标 / 间距 / 控件大小对不齐」

不触发：

- 无 figma 设计稿（按口述实现）
- 非 UI 改动
- 用户明确 loose 严格度（只要版式骨架 + 颜色 token，间距 / 字号允许 ±2pt）

## 四工具分工（核心心智模型）

| 工具 | 给你什么 | 数值可信度 |
|---|---|---|
| `get_design_context` | **布局结构 + 参考 HTML/CSS 骨架**：Auto Layout（itemSpacing / 各边 padding / 对齐 / FILL-HUG-FIXED）+ 一段参考代码 + 资源下载 URL | ❌ 代码里的数值按目标框架刻度吸附过（`gap-2`/`p-4`）、**不是测量值**；但结构 / Auto Layout 语义 + HTML 骨架**只在这里** |
| `get_metadata` | **精确像素几何**：逐节点 id / 类型 / 名字 / x / y / width / height（含子节点） | ✅ 唯一精确像素来源 |
| `get_variable_defs` | **精确 token**：spacing / size / radius / color 变量名 → 值 | ✅ 间距 / 图标尺寸 / 圆角的设计本意 |
| `get_screenshot` | 渲染后的栅格图，长边被 maxDimension 压缩 | ⚠️ 只看版式 / 确认节点被画出来，**不能拿来量**像素 |

烘焙 = **拿 get_design_context 的结构骨架，把里面被吸附的数值用 get_metadata（尺寸）+ get_variable_defs（间距/token）覆盖、按倍率换成 pt**。别指望一个工具全给：结构 ← design_context，精确像素 ← metadata，token ← variable_defs。

## 烘焙 SOP

1. **选准节点**：先对目标节点 `get_metadata` 看层级树，确认抓的是**可见组件本体**、不是带 padding 的 wrapper / 热区。URL 的 node-id 选错（指到 page / 父节点）会拿到整屏几何。

2. **算设计基准倍率（必先算、别默认 1）**：`倍率 = figma frame 宽(px) / 目标设备点宽(pt)`。=1 才 px==pt（frame 宽正好 = 375/390/393/414/428/430）；@2x/@3x（frame 786/1179）或非整设备宽稿（1440 web 稿、393 设备放 414 稿）倍率 ≠ 1，所有布局数都要除它。**陷阱**：跳过这步会让每个数被同一常数带偏、比例自洽 → 肉眼 + 压缩图自测都看不出来。烘焙时只应用**一次**，冻进 HTML 的数全是 pt。

3. **取结构骨架** ← `get_design_context({nodeId, forceCode: true})`：拿 Auto Layout 结构 / 对齐 / sizing 模式 / 图层层级 + 一段参考 HTML/CSS + 资源下载 URL。`forceCode: true` 防大节点退化成只返回 metadata；仍只回 metadata（无结构 / 无资源 URL）或返回稀疏数据（只剩 `<frame>`/`<text>` 标签没样式）→ 走下方「大节点退化兜底」逐子节点分级重抓，**别直接手写骨架**（手写救不回切图资源 URL）。**保留结构、不信里面的数值**。

4. **取精确数覆盖骨架数值**：
   - 尺寸 ← `get_metadata`：逐图标 / 关键控件子节点的精确 w/h/x/y，按倍率换成 pt
   - 间距 / 圆角 ← `get_variable_defs` token 为先（token 化的精确无歧义）+ design_context Auto Layout 的 itemSpacing / padding **属性值**核对（不是生成代码 class）；metadata x/y 差只当交叉验证（SPACE_BETWEEN / padding / stroke 外溢会让它与声明值不符）
   - token ← `get_variable_defs`（变体在精确变体节点上调）：size / spacing / radius / color 变量名 → 值，不只颜色

5. **烘焙成冻结 HTML** → `.specs/<slug>-assets/figma-<nodeId-safe>.html`（`<nodeId-safe>` = nodeId 把 `:` 替换成 `-`）：把 step 3 的结构骨架 + step 4 覆盖后的精确数值写成自包含 HTML/CSS，数值一律存 pt，token 同时保留值和名称。implementation owner 只读该工件。

6. **截图只做视觉参考** ← `get_screenshot({nodeId, maxDimension: 4096})` 冻成 PNG：描边（outside/center）、阴影、模糊画在布局框外 → 不算尺寸。**PNG = 视觉真相**（颜色 / 阴影 / 渐变 / 渲染观感），**HTML = 测量真相**（尺寸 / 间距 / pt）。

7. **图标专项（frame vs glyph）**：Figma 图标常是固定外框（24×24）裹更小字形（~20）+ 光学留白。metadata 报**外框**、导出 SVG viewBox 报**字形**。box 设成 metadata 外框尺寸（换 pt）；记「外框 X×X / 字形约 Y」进 HTML 注释。有 Code Connect 优先让图标解析到真实组件、别从几何重推。位图资源 @1x/2x/3x 各导一份进 asset catalog（见 `~/.claude/skills/figma-asset-export/SKILL.md`），不在 HTML 里换算。

## 大节点退化兜底（design_context 返回稀疏数据时）

设计稿过大时 `get_design_context` 可能只返回稀疏标签或 metadata。关键缺失是结构骨架和资源 URL；直接手写无法恢复资源，implementation owner 会被迫用近似图标。

**阻塞，不在稀疏态进下一步**。对退化节点 N 逐子节点分级重抓：

1. `get_metadata(N)` 枚举 N 的一级子节点 id + 各自相对根的 x/y/w/h。
2. 对每个一级子节点单独 `get_design_context({nodeId, forceCode: true})` —— 子节点更小、多半不再退化，拿回各自的结构 + 资源 URL。
3. 仍退化的子节点再往下拆一层（递归），**深度上限 3 层**（或累计子节点数上限），防 MCP 调用爆炸。
4. 超上限仍稀疏的子树 → 退回手写骨架，并在最终 plan 的风险/未决项中标明缺失资源 URL；实现前需要用户或 Root 决定是否接受。

**坐标对齐陷阱（合并必做）**：单独重抓的子节点，其结构 / 坐标可能相对**自身原点 (0,0)**、不是父 frame。合并回冻结 HTML 时**必须**用 step 1 metadata 里每个子节点**相对根的 x/y** 做偏移，否则子节点全堆在 (0,0) —— 静默毁掉版面、肉眼 + 压缩图自测都看不出（同倍率陷阱那类）。

烘焙只执行一次；设计源未变化时实现和 UI 验收都复用冻结工件。

## 冻结 HTML 的内容

烘焙后的 HTML 等价于这张逐元素精确表（直接编码进 HTML/CSS，数值已是 pt）：

| 元素 | 精确尺寸 (pt) | 间距 / 位置 | token | 备注 |
|---|---|---|---|---|
| frame | 375×200 | 外 padding 16 | `spacing/md=16` | — |
| icon: bell | 24×24（外框） | 到 title gap 8 | `icon/size/md=24` | 字形约 20、留白 2 |
| title | 高 22 | baseline 与 icon 居中 | `text/title 17pt semibold` | — |
| primary button | 高 44 | — | `radius/md=8` | — |

尺寸 = metadata 换 pt；间距 = variable_defs token 为先 + design_context itemSpacing 核对；token = variable_defs；对齐/sizing 来自 design_context。最终 plan 或 ExecPlan 只记录工件路径、倍率、token、严格度和切图清单，不内联逐元素表。

## preview.html 还原度预览（strict 任务）

冻结 PNG 和 measurement HTML 之外，strict 任务默认在烘焙末尾生成第三份工件 `.specs/<slug>-assets/preview.html`，并连同冻结 PNG 一起 `open` 给用户在浏览器判还原度，再等实现授权。PNG 仍是颜色、阴影和图标观感的真相源。

触发：strict figma→code 任务。loose 跳过（只要骨架 + 颜色 token、无需复刻）。

生成规范（每 slug 一份合并文件）：

- 自包含单文件：完整 `<!DOCTYPE html>` + 内联 CSS/JS、**无任何外部资源**（CDN / 外链字体 / 远程图都不行，CSP 与离线都要能开）。字体用系统栈 `-apple-system,"SF Pro",system-ui`（macOS 上即 SF Pro）。
- 每个冻结 node 一个 native pt 宽手机框（倍率已应用，宽 = 设备点宽如 402），多 node **并排**（flex-wrap）+ 各框标 node-id + 态名。
- 几何来自 measurement HTML（间距 / 尺寸 / 圆角 / 字号 pt 1:1）；颜色 / 玻璃 / 渐变来自 PNG（玻璃用 `backdrop-filter: blur` 近似）；图标用内联 SVG 近似（SF Symbol 不可用）。
- 有状态变体（折叠↔展开 / 选中切换 / 空↔满态）→ 加最小内联 JS 点击切换，默认展示主态。
- 顶部一条 caveats banner：「近似复刻：judge 版式 / 间距 / 结构；PNG = 视觉真相（玻璃 / 色 / 图标更精细）；agentName 等占位已用运行时值替换」。
- 文件名固定 `preview.html`。烘焙时一次性生成；只有设计源（file/node/version）或选中 node 集合变化才重建，且只更新受影响 node 的手机框并同步对应 PNG/measurement HTML 与最终 plan。实现迭代、code review 和验证轮次不重建、不改写该文件。

## 硬约束

- ❌ 不把 `get_design_context` 生成代码里的尺寸 / 间距当精确值冻进 HTML（被框架刻度吸附过，尤其 Tailwind / 设计系统 client）—— **必须**用 metadata（尺寸）/ token（间距）覆盖后再冻
- ❌ `get_design_context` 返回稀疏数据（仅 metadata / 无资源 URL）时直接手写骨架进下一步 —— 必走「大节点退化兜底」逐子节点分级重抓（手写救不回切图资源 URL）；合并子节点必按 metadata 相对根 x/y 偏移
- ❌ 不从 `get_metadata` 找 Auto Layout / 对齐 / strokeAlign / effects（它只有位置 / 尺寸）；间距别只信它的 x/y 差
- ❌ 不拿 `get_screenshot` 栅格目测像素下结论
- ❌ implementation worker 不 live 拉 Figma 测量或重烘焙共享工件；缺失/过期时交回 Root 更新
- ❌ 设计稿标注值不写进项目文档（AGENTS/CLAUDE/knowledge/README）—— 文档以真实代码数据为准，引用代码常量 / token 定义路径；设计值只留在 `.specs/` 冻结工件与最终 plan
- ✅ HTML 数值一律 pt（倍率烘焙时应用一次）；尺寸 ← metadata，间距 ← variable_defs token + design_context itemSpacing，结构 ← design_context
- ✅ 图标按外框尺寸定 box；有 Code Connect 优先解析到真实组件

## 在 plan-first delivery 里的位置

- **Root/source prep**：在 Default mode、源码写入前，为最终 plan 选定的 node 生成 `.specs/<slug>-assets/figma-*.png` 与 `figma-*.html`。
- 同时记录 Figma file/node/version（provider 提供时）和全部冻结工件 SHA-256；没有 immutable version 时，以这组冻结工件的 bundle digest 作为 UI review 的 design identity，验收期间不再拉 mutable latest。
- 工件若暴露新的可观察行为、scope、架构或验收决策，Root 必须回到 DISCOVER/PLAN_READY 更新 authoritative plan；不能让后生成的 HTML/PNG 静默覆盖最终 plan。
- **implementation owner**：读取冻结 HTML/PNG 实现，不 live 拉取设计测量。
- **ui-reviewer**：可运行 build PASS 后按冻结 PNG、严格度和用例做视觉对照；精确尺寸参考 HTML。

## Why（核心）

`get_design_context` 生成代码里的数值可能被框架刻度吸附；精确像素用 `get_metadata`，token 用 `get_variable_defs`，冻结时统一换成 pt。
