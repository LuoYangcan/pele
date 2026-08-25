---
name: scan-trigger-docs
description: 扫描项目 AGENTS.md/CLAUDE.md 中的 trigger-on-touch 文档索引，并全文读取与本轮计划、写入或 review 范围相交的文档。项目没有索引或范围明确无交集时跳过。
---

# Scan trigger-on-touch docs

普通 Markdown 链接不会自动把目标正文注入 context。任何负责规划、实现或 review 的 agent 都要按自己的实际范围独立执行本流程。

## 1. 定位项目根

从 cwd 向上找最近的 `AGENTS.md` 或 `CLAUDE.md`。在 worktree 中使用 worktree 自己的文件，不跳回主仓库。

```bash
project_root="$PWD"
while [[ "$project_root" != "/" \
  && ! -f "$project_root/AGENTS.md" \
  && ! -f "$project_root/CLAUDE.md" ]]; do
  project_root="$(dirname "$project_root")"
done
```

两者都不存在则结束。

## 2. 读取索引

host 已把 always-load 文件注入 context、或项目自带专用 scan skill 时，以注入内容与项目版为准，不重复 Read；否则完整读取存在的 `AGENTS.md` 和 `CLAUDE.md`。查找以下形式及语义等价写法：

- “改动以下任一范围前先读该文档”；
- “trigger-on-touch / touch 前必读”；
- 指向子系统索引的普通 Markdown 链接。

若 always-load 文件把触发表委托给另一个索引文件，完整读取该索引后再判断。

## 3. 匹配本轮范围

对每个 trigger 记录 doc 路径和触发路径/类型/模块/概念。用本轮计划触达路径、当前 ownership、实际 changed paths 或 review scope 匹配：

| 信号 | 处理 |
| --- | --- |
| 文件直接位于触发路径 | 读取 |
| 类型、函数或模块名命中 | 读取 |
| 功能语义与 doc 主题相关 | 读取 |
| 明确跨平台/跨模块且无交集 | 跳过 |
| 边界不确定 | 读取 |

范围在执行中扩大时重新匹配新增部分；无需重复读取同一版本的文档。

## 4. 读取并应用

全文读取所有命中文档，不用 `grep/head` 片段替代。文档内若有递归 trigger，按同样规则继续。

- 规划：把会改变实现或验收的约束写入最终 plan。
- 实现：遵守 invariant；若它与 plan 冲突，暂停写入并回到决策层。
- review：以文档为证据检查最终 diff，只报告当前 diff 的偏离。

项目存在 `.cursor/rules/*.mdc` 时，仅在文件名/前言显示与本轮范围相关时全文读取。

## 输出

调用方可在结构化结果中附：

```yaml
trigger_docs_read:
  - <repo-relative path>
```

本 skill 不修改 marker、不缓存跨 session 结果，也不替代规划、实现或 review。
