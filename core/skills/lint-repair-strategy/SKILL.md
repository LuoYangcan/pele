---
name: lint-repair-strategy
description: 修 SwiftLint / SwiftFormat 报错时按 lint 类别选方向，防止为绕 file_length/type_body_length 把代码挪进无语义 extension。Use whenever implementation owner 收到 lint warning/error。Skip when build error 未修、用户明确要求局部 disable、或 issue 与 lint 无关。
---

# lint-repair-strategy

## 触发

任一即触发：

- 跑 `just check` / SwiftLint / SwiftFormat 产出 warning 或 error 且要修
- verifier 或 `/review` 报告里的 `lint-error` / `lint-warning` 要落地

## 不触发

- build error 未修完（先修编译）
- 用户明确「这一行加 swiftlint:disable」/「先 disable 跑通」
- 收到的 issue 是非 lint 类（mock-data / scope-violation / behavior-mismatch）

## 修复决策表

按规则名找类别，每类有**优先修法 → 兜底**。

### A 类：纯格式 / 命名 / 未使用

规则示例：`trailing_whitespace` / `vertical_whitespace_*` / `opening_brace` / `colon` / `comma` / `operator_usage_whitespace` / `unused_import` / `unused_declaration` / `identifier_name` / `type_name` / `file_header`

**修法**：直接 `just fix` / SwiftFormat / 手改一行。不需要重组代码。

### B 类：长度 / 复杂度（**最容易被偷懒抽 extension**）

规则示例：`file_length` / `type_body_length` / `function_body_length` / `line_length` / `cyclomatic_complexity` / `nesting` / `function_parameter_count`

**按顺序问根因**：

1. 这个类型 / 函数**职责膨胀了吗**？
   - 是 → 按 use-case 拆**功能子模块**（新 type / 新 service / 新 reducer / 新 view component），不要"挪到 +Helpers"
   - 例：`HomeViewController` 1200 行 → 拆 `HomeFeedSection`、`HomeRecommendationLogic` 两个独立类型，**不是** `HomeViewController+Helpers.swift`

2. 这个函数把**多个语义步骤**揉一起了吗？
   - 是 → 提取**有语义名**的子函数（`fetchProfile()` / `validateInput()` / `dispatchEvent()`），不要 `helper1()` / `_doStuff()`

3. 逻辑分支太多（复杂度类）？
   - 能在现有 boundary 内按语义拆函数、closed enum/switch 或 table-driven dispatch → 局部修复
   - 只有修复必须改变模块 ownership/依赖方向、public seam、state source-of-truth 或 IO boundary → 才升级到 `architecture-first`

4. 确实合理就长？
   - SwiftUI body / DSL 配置 / generated code → 在该**单个**文件顶部 `// swiftlint:disable type_body_length` + 一行 why
   - 不要全局 disable

**硬禁止**：

- ❌ 仅为绕 `file_length` / `type_body_length` 抽出 `<Type>+Helpers.swift` / `<Type>+Utilities.swift` / `<Type>+Lint.swift` / `<Type>+Private.swift` / `<Type>+Internal.swift` 这类**无语义 extension 文件**
- ❌ 把私有方法成块挪到 `<Type>+xxx.swift` 当过墙工具
- ❌ 一个文件多 extension 仅为 line 数控制

**允许的 extension 抽取**（合法 case、不在硬禁止）：

- ✅ `<Type>+Codable.swift` —— Codable 是独立 concern
- ✅ `<Type>+Equatable.swift` / `<Type>+Hashable.swift` —— protocol conformance 独立
- ✅ `<Type>+CollectionView.swift` —— UICollectionViewDelegate 实现是独立 protocol
- ✅ `<Type>+Analytics.swift` —— 埋点是独立 cross-cutting concern
- 判断标准：extension 文件名映射到**清晰语义 concern**（protocol / cross-cutting / 子系统），不是"放余下的代码"

### C 类：局部结构信号

规则示例：`large_tuple` / `cyclomatic_complexity`（同 B）/ `function_parameter_count`（同 B）/ `force_try`

**修法**：先在现有 boundary 内恢复语义；lint 本身不触发架构选型。

- `large_tuple` → 建有业务含义的 local/nested struct
- `function_parameter_count` 超 → 真正同生命周期的参数才组成 config/input struct；否则拆语义步骤
- `cyclomatic_complexity` 超 → 提取语义函数，或对封闭 case 使用 enum/switch/table
- `force_try` → 若失败是合法路径则改为 `throws`/`Result` 并让现有 owner 处理；静态不变量可用带理由的局部 disable

只有上述修复会改变 durable boundary 时，才把诊断证据交给 `architecture-first`；不要因为规则名自动升级。

### D 类：边界 / 安全

规则示例：`force_unwrap` / `force_cast` / `implicitly_unwrapped_optional` / `discouraged_direct_init`

**修法**：通常是 API 设计问题、不是改一行。

- `force_unwrap` 多 → IUO 应改 `Optional` + guard let
- `force_cast` 多 → 该用 protocol / generic 重设计
- 一行就能改 + 上下文确定不为 nil → `// swiftlint:disable:next force_unwrap` + 一行 why

## 输出 plan

skill 不直接改代码。返回结构化决策（写进 chat 给调用方）：

```yaml
lint_repair_plan:
  - rule: <SwiftLint 规则名>
    category: A | B | C | D
    action: fix-in-place | extract-semantic-function | introduce-local-type | escalate-material-boundary | swiftlint-disable-with-reason
    target_location: <文件路径或受影响 boundary>
    notes: <一句话说做什么 / 不做什么；如果是 B 类，明确说不抽 +Helpers>
```

调用方拿 plan 自己落地。落地后跑项目的 lint/check 命令（如 `just check`）验证。

## Why 核心

把代码搬进无语义文件只会物理变短、组织变散；先判断 lint 暴露的真实职责或 API 问题。
