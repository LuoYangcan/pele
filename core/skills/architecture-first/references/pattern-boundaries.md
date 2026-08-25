# 行为与对象模式边界

仅在 `architecture-first` 已确认存在未决 material choice，且差异主要来自行为、创建或适配方式时读取。局部分支、lint 或“以后可能扩展”不足以触发。

## 先确定变化轴

| 变化轴 | 优先形态 | 不该升级的情况 |
| --- | --- | --- |
| 封闭且稳定的少量 case | `enum` + `switch` / table-driven dispatch | 分支只在一个现有 boundary 内 |
| 同一动作有多个真实、可替换实现 | Strategy | 当前只有一个实现或差异只是参数 |
| 行为由对象当前状态和合法迁移决定 | State / 显式状态机 | 独立 boolean 足以表达且无迁移不变量 |
| 创建端必须隐藏多个具体实现 | Factory / registry | `init` 已经是唯一明显入口 |
| 外部/旧接口与内部稳定契约不匹配 | Adapter | 只是无逻辑转发或不需要替换依赖 |
| 正交能力需要独立组合 | Decorator / middleware | 能力互斥，或只会存在一层 |
| 多个独立步骤需要插拔、重排或短路 | Pipeline / Chain | 步骤固定且共享大量中间状态 |
| 一项事件有多个独立生命周期消费者 | Observer / event stream | 一对一同步调用即可表达 |

## 决策约束

- 先沿用项目最近 precedent；除非它违反当前 invariant，不引入第二套模式。
- 只有 seam 两侧具有不同变化节奏、多个实现、跨模块依赖或测试替换价值时才建 protocol/interface。
- 一个调用方、一个实现、只 forward 的 wrapper 通常不是 seam。
- 模式必须减少调用方知识或集中不变量；只增加类型和跳转层则拒绝。
- 选择 State 时记录合法/非法迁移、状态 owner 和并发序列化点。
- 选择 Observer/event stream 时记录订阅 owner、释放时机、顺序和错误传播。
- 选择 Factory/registry 时记录注册 owner、缺失实现行为和可见范围。
- 选择 Adapter 时内部契约应由业务需求决定，不照抄第三方 API。

## 最近候选比较

只比较最接近的两个形态：

- `switch` vs Strategy：case 是否开放增长，调用方是否需要替换实现；
- Strategy vs State：差异来自调用意图，还是同一对象的当前状态；
- direct call vs Observer：消费者是否确实多方且生命周期解耦；
- direct dependency vs Adapter/port：依赖是否 volatile、跨边界或需要替身；
- sequential function vs Pipeline：步骤是否独立、可组合且有稳定输入输出。

把最终选择、最近被拒候选及测试边界写进 `architecture_decision`；不要生成模式教程或示例代码。
