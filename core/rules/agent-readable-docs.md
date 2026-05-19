# Agent-Readable 文档原则

写或改 `~/.claude/` 下的 rule / agent / skill / template 文件、项目 AGENTS.md / CLAUDE.md / docs/*.md 时，文档以 **agent 为目标读者**，不为人类阅读优化。

## 触发

满足**任一**即触发：

- 写 / 改 `~/.claude/{rules,agents,skills,templates,commands}/*.md`
- 写 / 改项目根 `AGENTS.md` / `CLAUDE.md`（user-level 或 project-level）
- 写 / 改项目 `docs/*.md` 里被 AGENTS.md / CLAUDE.md 引用的「trigger-on-touch」类知识文档

## 不触发

- 写 `.specs/<slug>.md`（spec 本来就 agent-targeted，遵循 spec-template）
- 改代码注释 / commit message / PR 描述
- 用户自己的笔记 / 一次性临时文档

## 删什么

- **「Why」段的展开叙事**（保留 1-2 句核心因素，删整段论述）
- **「设计取舍」/「设计意图」/「Why 这套设计」**整段
- **「风险与兜底」整段叙事**（边角约束放进相应 SOP 步骤里，不单列段落）
- **历史 / 废弃说明 / 「曾经 X 后来改成 Y」**
- **类比 / 比喻 / 故事化叙述**（「就像 / 等于 / 同源于 / 跟 X 一样」）
- **重复修辞 / 强调语气**（同一约束反复写多次只留一次；过量 ⚠️ / ❗ / **强调** 删）
- **给文档维护者的元说明**（「这个判断由你自己列清楚」「install.sh 后会从 X symlink 过来」）
- **解释 Why 是为读者好处**（「这样你能 X」「让你 Y 时不被打扰」）

## 保留什么

- 触发条件 / 不触发条件（agent 决策入口）
- SOP 步骤（agent 执行流程）
- 决策路由表（用户反馈 → 处理路径 / 状态 → 下一步）
- prompt 模板 / Agent({}) 调用模板
- 字段定义 / 结构化结论 schema / YAML / JSON 例
- 硬约束（禁止 / 必须 / ❌ / ✅ 列表）
- 工具调用方式 / 命令 / 路径
- 「Why」的核心一句话（agent 推理 edge case 时需要的因果链）
- 跨 rule / agent / skill 的关系链接（导航用）

## 自检（写完每段问一遍）

- [ ] 这段如果删了，agent 还能正确执行规则吗？能 → 删
- [ ] 这段是给文档维护者 / 用户看的吗？是 → 删
- [ ] 这段是同一约束的第 2+ 次重复吗？是 → 删
- [ ] 这段用类比 / 比喻 / 故事化语气吗？是 → 重写成直接约束
- [ ] 这段超过 5 行但只表达 1 个规则吗？是 → 压缩成 1-2 行

## 与现有 rule 的关系

- `spec-before-code.md`：spec 文件不属本 rule 范围，按 spec-template 走
- `commit-message.md`：commit message 不属本 rule 范围
- 所有其他 rule / agent / skill 的更新都属本 rule 范围
