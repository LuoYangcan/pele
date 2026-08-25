---
name: agent-readable-docs
description: "Compact agent-consumed operational Markdown without changing its behavioral contract. Use when creating or modifying AGENTS.md/CLAUDE.md; rule, agent, skill, template, or command Markdown under ~/.claude or project equivalents; or a new/existing knowledge document indexed for agents. Apply inline after content decisions to canonicalize prose and indexes. Skip read-only discovery/application of existing docs, format/link/rename-only edits, generated docs, ordinary README/API/user-facing docs, ExecPlan/spec, code comments, and commit/PR/release text. skill-creator owns skill functionality/frontmatter/resources/evals; scan-trigger-docs owns read-only discovery."
---

# Agent-readable docs

把本 skill 当作同一 Root 的内联、语义保持压缩步骤。不要创建独立阶段、subagent、artifact 或确认回合。

## 先判文档角色

| 角色 | 保留形态 |
| --- | --- |
| Always-load 索引（AGENTS/CLAUDE） | 只保留入口、优先级和按需链接；SOP 下沉 |
| On-demand 执行文档（rule/agent/skill/command/template） | 入口假设、输入、步骤、输出、失败路由和验证 |
| 长期知识/trigger-on-touch 文档 | 稳定事实、invariant、owner、适用范围和失效条件 |
| 双受众文档或 UI metadata | 保留必要的人类说明；只压缩 agent 执行片段 |

目标并非 agent-consumed operational Markdown 时，返回 `agent_docs: not_needed`，不要套本规则。

## 原地改写

1. 完整读取目标、直接入口索引，以及定义同一合同的直接引用；确定唯一 canonical owner。
2. 冻结不得静默改变的语义：
   - trigger、skip、scope、precedence 和 authority；
   - 权限/安全边界、输入输出/schema、状态转移；
   - failure、retry、rollback、verification；
   - 命令、路径、工具契约和会改变 agent 决策的非显然因果。
3. 通读全文后把新内容并入所属章节与既有结构，不得只在文末追加本次改动的记录；在原位置合并重复规则和相邻说明。删除历史叙事、任务 trace、类比、重复强调、解释代码 what 的段落，以及不影响决策的展开 Why。
4. 不按“设计意图”“风险”“兜底”等标题机械整段删除；把仍影响执行的约束并入对应步骤、失败路由或验证。
5. 同一事实只保留一个 canonical 定义，其他位置改为短指针。来源冲突时先暴露冲突，不按篇幅擅自选边。
6. UI 尺寸、间距、颜色、token 等数值以真实代码为唯一真相源：项目文档不记录设计稿（Figma 等）标注值，需要时引用代码常量 / token 定义的路径；设计值只存在于任务期冻结工件与最终 plan。
7. 只有能降低 always-load 成本时才下沉 reference；保持一层直达，不创建索引套索引。

## 索引修改

- 先更新已有条目，避免 append-only 新增近义入口。
- 每个条目只表达一个路由决策：触发条件、用途、链接；实现细节留在目标文档。
- 新建 agent 知识文档时，同一修改里加入入口索引；移动或删除时同步所有直接链接。

## 收尾

重新通读改后合同，确认上述冻结语义与适用项目规则未漂移。格式、frontmatter、local links 和 installer 等机械验证沿 host/meta 配置流程执行；本 skill 不新增 app build 或第二次文档验收。

已经紧凑且 canonical 时返回 `agent_docs: no_change_required`。否则直接更新目标文档，不另写总结文件。

## 职责边界

- `skill-creator`：决定 skill 功能、frontmatter、资源布局、验证与 eval；本 skill 只压缩其 agent-facing prose/index。
- `scan-trigger-docs`：只读发现并应用项目知识；本 skill 只在创建或修改正文时使用。
- `plan-first-delivery`：决定产品改动是否需要长期文档更新；本 skill 不为普通改动强制留痕。
- `exec-plan`：一次性交接计划不属本 skill 范围。
