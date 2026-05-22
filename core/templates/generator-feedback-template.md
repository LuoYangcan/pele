# Generator → Planner 反馈

> generator 在写代码时遇到 spec 没覆盖的不确定点，写在这里给 planner 处理。
>
> 文件位置：`.specs/<slug>-feedback.md`（worktree 根，和 spec 同 slug）。
>
> 多轮反馈时**追加**新章节（不覆盖旧的），按 iter 编号往下加 —— 历史保留供 planner / 用户回溯。
>
> 文件由 generator Write / Edit；planner 二次调用时只 Read，不修改本文件（planner 的回应写进 spec 主文件第 7 节或更新日志）。

---

## iter-N · `<YYYY-MM-DD HH:MM>`

> 每次 generator 触发「需要 planner 更新 spec」就追加一个 `## iter-N` 节。N 从 1 起递增。

### 触发场景

- **当前在做的子任务**：`task-X`（spec 第 2 节的 ID）
- **进展到哪一步**：<例：刚改完某 State 类准备改对应 ViewController 的核心方法，发现 spec 没说某个并发条件下的优先级>
- **触发时机**：<动手前 / 动手中 / 编译完准备进下一个子任务时>

### 不确定点

> 一条疑问写一段。多个疑问就分多个小节（####），每段独立。

#### 疑问 1: <一句话标题>

- **具体疑问**：<把不确定的事讲清楚 —— 不是 "我不确定怎么做"，是 "X 在 case A 应该 Y 还是 Z">
- **当前 spec 里相关的章节**：<例：第 6 节硬约束写「不能改 ChatPayload」，但本子任务必须读它的 reply 字段判断 UI 优先级 —— 是只读还是真不让动？>
- **可能的几种解释 / 选项**：
  - 选项 A: <一句话 + 影响>
  - 选项 B: <一句话 + 影响>
  - 选项 C: <如果想得到，一句话 + 影响>

#### 疑问 2: <一句话标题>

（如有）

### 影响 spec 的字段

> generator 自己评估这些疑问会让 spec 哪一节需要改。planner 二次调用时按这里的提示精确编辑、不需要全文重读。

- 可能要改：<第 N 节，写改的方向 —— 例：第 6 节硬约束「不能改 ChatPayload」需要细化为「不能改 ChatPayload 枚举 case，但允许在 extension 里加 computed property」>
- 可能要新增子任务：<是 / 否；如果是，写一句话描述 —— 例：「新增 task-X.5: 在 ChatPayload extension 里加 isReplyOrigin computed」>
- 不动的章节：<列出来 planner 不要去碰的章节，避免误改 —— 例：第 4 节测试用例不需要动>

### generator 暂时怎么处理

> generator 在等 planner 回应期间已经做了什么、卡在哪。planner 拿到这个能判断要不要让 generator 回滚某些改动。

- ✅ 已经做完且不会回滚的事：<例：已经在某 State 类加了新字段/方法，纯加法不破坏 spec>
- ⏸️ 已停手、等回应的事：<例：还没改对应 ViewController 的核心方法，等 planner 拍板设计细节>
- 🤔 已经写了但可能回滚的事：<例：暂时按选项 A 写了 placeholder 实现 + 注释 `// PLANNER-FEEDBACK iter-N: 待澄清后回来改`，方便编译过；planner 选 B/C 就改回来>

---

## iter-N+1 · `<YYYY-MM-DD HH:MM>`

（下一轮反馈追加在这里，结构同上）
