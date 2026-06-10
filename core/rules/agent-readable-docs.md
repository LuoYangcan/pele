# Agent-Readable 文档原则（已迁 skill）

正文已迁移到 `~/.claude/skills/agent-readable-docs/SKILL.md`。触发时通过 `Skill(agent-readable-docs)` 加载。

## 触发摘要

- **触发**：写 / 改 `~/.claude/{rules,agents,skills,templates,commands}/*.md` 或项目 AGENTS.md / CLAUDE.md / docs/*.md（被 trigger-on-touch 引用的）。
- **不触发**：写 spec / 改代码注释 / commit message。
- **核心**：以 agent 为目标读者，删 Why 叙事 / 设计取舍 / 历史 / 类比 / 重复修辞 / 给维护者的元说明；保留触发条件 / SOP / 路由表 / prompt 模板 / 字段定义 / 硬约束 / Why 核心一句。
