# UI state 与事件流边界

仅在 `architecture-first` 已确认 source-of-truth、状态生命周期或跨屏事件流存在未决 material choice 时读取。单个 view 的局部 state、普通 binding 或沿用既有 UI 架构不触发。

## 必须冻结的事实

- 哪个对象是 authoritative state owner；
- state 生命周期是 view、flow、feature、session 还是 process；
- 用户事件、异步结果和外部事件如何进入；
- IO/effect 由谁启动、取消和回传；
- 是否存在 dual write、循环更新或多个 competing source-of-truth；
- 测试需要观察 state、event、effect 还是导航结果。

## 形态路由

| 约束 | 优先形态 | 边界要求 |
| --- | --- | --- |
| view-local、短生命周期、无共享 | 平台原生 local state / 简单 MVC | state 不外泄，不建全局 store |
| 单 screen/feature 的可测派生状态与异步入口 | MVVM / Presenter | ViewModel/Presenter 不持有具体 view toolkit；effect dependency 可注入 |
| 明确状态迁移与非法事件 | 显式 state machine | 单一 transition owner；迁移和并发顺序可测 |
| 多来源事件、复杂 effect、需要可追踪 action | Reducer / unidirectional flow | 单一 store；mutation 只在 reducer/transition；effect 明确返回 |
| 跨 screen 的 flow/navigation ownership | Coordinator/router | feature 不直接拥有全局导航；避免 God coordinator |
| 跨 feature/session 的共享状态 | 上提到最小共同 owner | consumer 只读/发 event；不复制可变 state |

## 选择规则

- 项目已采用稳定的 UI state shape 时优先复用；屏幕行数或团队规模不是切换架构的充分理由。
- 一个简单页面不因“可测试”自动引入 store/reducer；先验证是否存在真实状态或 effect 复杂度。
- 不把网络、数据库、时间或随机数藏进 reducer/pure transition；通过 effect boundary 输入结果。
- 不用多个 ViewModel/store 各自维护同一业务实体；指定一个 owner 和明确同步方向。
- 导航若只是单点 push/present，直接调用现有 router；只有 flow ownership 跨屏时新增 coordinator seam。
- 引入新 state owner 时写清旧 owner 的移除顺序，禁止长期 dual write。

## Consequences 最低要求

在 `architecture_decision` 中记录：

- source-of-truth 及生命周期；
- event/effect 流向和取消点；
- 旧状态到新状态的迁移边界；
- transition、effect 和导航的 targeted tests。

不要输出 MVC/MVVM/TCA 百科；只说明为何当前 owner/flow 需要所选形态，以及最近候选为何无法满足不变量。
