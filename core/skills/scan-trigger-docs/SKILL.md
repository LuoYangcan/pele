---
name: scan-trigger-docs
description: Scan project AGENTS.md / CLAUDE.md for "trigger-on-touch" doc markers (`**改动以下任一范围前先读该文档**`) and Read full content of any docs whose touch ranges intersect this round's scope. Project AGENTS.md authors maintain these lists with hard-won counter-intuitive knowledge that doesn't surface from the codebase alone — markdown links like `[docs/x.md](docs/x.md)` are NOT auto-injected by Claude Code (only `@docs/x.md` syntax recurses), so manual Read is the only path. Use this skill from any subagent (planner / generator / executor) before deciding scope, writing code, or judging review issues. Skip when the project has no AGENTS.md / CLAUDE.md, or when the current round's touch range is provably outside every listed marker.
---

# scan-trigger-docs

把项目 `AGENTS.md` / `CLAUDE.md` 里所有「触发即必读」段落扫一遍，根据本轮**自己负责的范围**判断是否命中，命中就 Read 对应 doc 全文。

## 触发

由 subagent SOP 显式 invoke：

- **planner**：写 spec 第 6 节硬约束 / 第 7 节风险 / 第 4 节测试用例前
- **generator**：开始写代码前（拿到子任务范围后）
- **executor**：拿到 generator 改动文件清单、判断 review issue 前

也可以由主 agent / 别的 subagent 在需要"扫一遍项目反直觉知识"时手动 invoke。

## 不触发

- 项目根没有 `AGENTS.md` / `CLAUDE.md`
- 任务范围是修改 meta 配置（`~/.claude/` / `.cursor/` / `settings.json` / `Justfile` 自身）—— 这些和项目业务 doc 无关
- 任务是改 doc 自己（写 spec / 改 README / 改 AGENTS.md 某段）—— 你已经在写 doc，不需要再读 doc 触发清单

## 流程

### Step 1: 定位项目根的 AGENTS.md / CLAUDE.md

```bash
# 从 cwd 向上找项目根（含 AGENTS.md 或 CLAUDE.md 的最近祖先）
ROOT="$(pwd)"
while [[ "$ROOT" != "/" && ! -f "$ROOT/AGENTS.md" && ! -f "$ROOT/CLAUDE.md" ]]; do
  ROOT="$(dirname "$ROOT")"
done
[[ -f "$ROOT/AGENTS.md" || -f "$ROOT/CLAUDE.md" ]] || { echo "no AGENTS.md / CLAUDE.md found"; exit 0; }
```

注意：当前 cwd 在 worktree (`.worktrees/<slug>/`) 时，AGENTS.md 在 worktree 根；不要直接跑到主仓库读，worktree 的 AGENTS.md 可能已经被本轮 spec 修改过。

### Step 2: 用 Read 读 AGENTS.md 和 CLAUDE.md（两份都读）

不要用 grep 抽段落 —— 完整 Read 两份文件再判断。原因：

- CLAUDE.md 可能是 `@AGENTS.md` stub，但也可能项目作者改过、有自己的额外段落
- 触发 marker 的格式可能因项目而异（`**改动以下任一范围前先读该文档**` 是一种常见 marker 写法，其他项目可能写成 `## 触发：` / `> 改这里前先读...` 等）
- 完整读才能判断每条 marker 的语义边界

### Step 3: 抽出所有「触发即必读」段落

**通用 marker 格式**（项目作者维护这套约定时的标准写法）：

```
... 详见 [docs/<feature>.md](docs/<feature>.md)。**改动以下任一范围前先读该文档**：

- <具体路径范围 1>
- <具体路径范围 2>
- ...
```

关键字面要素：`**改动以下任一范围前先读该文档**：` 这串中文 marker（项目可能用其他语言 / 句式变体，见 Step 2 注解）+ 紧邻的 `docs/<feature>.md` 链接 + 后跟项目符号清单。

抽出 4 类信息：

1. **doc 路径**：紧邻 marker 的 `docs/*.md` 链接
2. **触发范围列表**：marker 后面的项目符号清单
3. **隐含的反直觉知识主题**：从 doc 路径名 + section 标题猜（仅供你判断「是否可能命中」的弱信号）
4. **段落出处**：AGENTS.md 还是 CLAUDE.md，第几节（写进你判断的引用）

### Step 4: 判断本轮范围是否命中（**宁严不松**）

对每条 marker，问自己：

> 本轮我负责的范围（spec 第 2 节子任务 / generator 改动清单 / 我要审的代码 / 我要写的硬约束）**有可能**触达 marker 列出的任一路径或概念吗？

判定原则：

| 信号 | 判定 |
|---|---|
| 子任务 / 改动文件路径**直接落在** marker 列出的目录 | 必命中 → Read |
| 子任务**修改的类型 / 函数 / 模块名**出现在 marker 列表 | 必命中 → Read |
| 子任务**功能描述**和 doc 主题语义相关 | 命中 → Read |
| 子任务和 marker 范围**完全不相关、跨平台 / 跨模块** | 不命中 → 跳过 |
| 不确定 / 边界模糊 | **默认命中** → Read（多读一份 doc 比漏一份反直觉知识便宜得多） |

### Step 5: 按命中清单 Read 对应 doc 全文

依次 Read 每条命中的 `docs/*.md`。**全文读**，不要用 grep / head 抽片段 —— 反直觉知识通常不在标题里、在中间正文。

如果 doc 内部又引用了别的 doc（递归 marker），按相同规则继续判断 + Read。

### Step 6: 补扫其他 agent 工具的项目级指引（按需）

`.cursor/rules/*.mdc` 是 Cursor IDE 的项目级规则文件，如果项目里有这类文件也应当扫描：

```bash
ls "$ROOT/.cursor/rules/" 2>/dev/null
```

如果存在，扫一眼文件名 + 前几行，判断是否和本轮范围相关。**不强制全文 Read**（数量多、内容偏 lint 级别），但 spec 第 6 节硬约束 / executor 审硬约束时可能用得上。

### Step 7: 在 SOP 后续阶段引用读到的内容

读完不是终点。SOP 的后续阶段（写 spec / 写代码 / 列 issue）要把读到的反直觉知识**显式落地**：

- **planner**：把对应约束写进 spec 第 6 节硬约束 / 第 7 节风险，引用 doc 路径
- **generator**：实现时遵守 doc 里描述的 invariant；如果 spec 没覆盖到的 doc 知识在实现时浮现新问题，按「不确定流程」走 feedback 文件
- **executor**：审 generator 是否符合 doc 描述的隐性契约；不符合就列 blocking issue 并引用 doc

## 输出契约

本 skill 自身**不**返回任何结构化结果给主 agent —— 它只是替 subagent 做"扫 + 读"的动作。读完的内容直接进入 subagent 自己的 context，subagent 在后续 SOP 阶段消费。

可选地（建议）：在 subagent 返回主 agent 时，结构化结论里加一句 `trigger_docs_read: [<list of doc paths>]`，主 agent 看到能在汇报用户时附带「本轮读了哪些 doc」，便于追溯。

## 不做的事

- ❌ 不替项目作者 *维护* trigger marker —— 那是项目的事
- ❌ 不缓存 / 不跳读 —— 每次 invoke 都重新扫一遍 AGENTS.md（项目 doc 会随 PR 演化，subagent 上轮读到的版本可能已过期）
- ❌ 不替 SOP 决定后续动作 —— 读完是为后续阶段提供原料，不替规划 / 不替写代码 / 不替判 review
- ❌ 不强制扫 `~/.claude/` 全局规则、用户级别 README、CHANGELOG —— 那些不在项目反直觉知识范围
