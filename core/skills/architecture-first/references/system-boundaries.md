# 模块、依赖与副作用边界

仅在 `architecture-first` 已确认模块 ownership、依赖方向、public seam 或 IO/持久化边界存在未决 material choice 时读取。单模块内的 helper、局部 service 或普通测试替身不触发。

## 边界事实

- 现有模块图和允许的依赖方向；
- public contract 的 owner、调用方和兼容窗口；
- volatile dependency、IO、时间、随机数、持久化分别位于哪层；
- 业务 invariant 能否独立于 framework/SDK 执行；
- migration、rollback 和旧调用方如何过渡。

## 形态路由

| 约束 | 优先形态 | 拒绝条件 |
| --- | --- | --- |
| 项目已有合法依赖方向和 owner | 沿用现有模块/API | 不为局部便利新建横向依赖 |
| 内层业务需要可替换的外部能力 | Port/interface + adapter | 只有一个局部调用且不跨 boundary |
| 第三方/legacy API 不应渗入业务 | Adapter | 内部接口只是原 API 的同形转发 |
| 业务规则可纯计算，IO 可集中 | Functional core + imperative shell | 业务本身几乎全是 IO 编排 |
| 多个调用方需要稳定的业务动作 | Application service/use case | 只是给单个函数换名字 |
| 多个子系统的常用编排要隐藏 | Facade | 调用方需要细粒度控制或只包一项调用 |
| 跨模块共享稳定业务能力 | 下沉到最小中立层 | 共享只是代码相似、语义会独立演化 |

## 依赖规则

- 依赖箭头服从项目 invariant；不为局部复用新增 invariant 未授权的横向依赖。项目允许时仍要明确 contract owner 与演化责任。
- protocol/interface 放在需要稳定契约的一侧；不要默认放在实现旁或“common”垃圾桶。
- volatile SDK 只能通过 adapter 暴露业务需要的最小语义。
- IO、数据库、时钟和随机数的 owner 必须显式；需要 deterministic test 时从 boundary 注入。
- public contract 变化要记录 source/binary compatibility、版本窗口和调用方迁移顺序。
- 新 shared module 必须有明确 owner、依赖预算和至少两个真实消费者；否则优先留在现有 boundary。
- 不以 Clean/Hexagonal 等名称替代具体模块图；决策必须写出谁依赖谁、谁拥有 contract。

## Consequences 最低要求

在 `architecture_decision` 中记录：

- affected modules 和新的依赖方向；
- contract owner、适配层和兼容策略；
- 数据/持久化迁移与 rollback（如适用）；
- boundary tests、contract tests 和需要保持的现有调用方行为。

不要生成架构教程或项目无关示例；只输出当前仓库事实支持的边界选择。
