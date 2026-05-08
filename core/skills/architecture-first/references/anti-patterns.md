# 4 类「打补丁」反例 + 重构方向

SKILL.md 主决策框架第 II 节「反补丁」的延伸资料。看到任一类信号时停下，对照下方的重构方向选替代方案。

> 例子用 Swift / iOS 风格，但思路语言无关。

---

## 1. 在已有函数里加 `if/else` 特判 / boolean flag

### 触发信号

- 函数已经有 2-3 个 `if/else` / `switch case`，再加第 4 个
- 函数签名增长：`func send(_ msg: String, isUrgent: Bool, retryOnFailure: Bool, mode: Int)`
- 调用方需要传一堆「这个场景才用」的参数，且参数之间相互排斥（`mode == .a` 时 `isUrgent` 被忽略）
- 函数体里出现 `// for case A` / `// for case B` 这类注释
- 一个函数同时 handle 「正常用户消息」「系统消息」「错误消息」「skill 消息」

### 为什么是反模式

每加一个 case，**所有其他 case 的开发者**都要重新读一遍这个函数，确认自己的 case 没被影响。N 个 case 的相互干扰是 N²，不是 N。3 个 case 还能撑，到第 5 个就没人敢动了。

### 重构方向

**Strategy 模式**——把行为差异封装成同一接口的不同实现：

```swift
// ❌ 补丁堆叠
func send(_ msg: Message) {
    if msg.isSystem {
        // ... 20 行系统消息逻辑
    } else if msg.isError {
        // ... 15 行错误处理
    } else if msg.isSkillEvent {
        // ... 25 行技能事件
    } else {
        // ... 30 行普通消息
    }
}

// ✅ Strategy
protocol MessageSender {
    func send(_ msg: Message) async throws
}
struct UserMessageSender: MessageSender { ... }
struct SystemMessageSender: MessageSender { ... }
struct SkillEventSender: MessageSender { ... }

// 调用侧用 factory / registry 拿到对应 sender，不再写 if/else
let sender = senderRegistry.resolve(for: msg)
try await sender.send(msg)
```

**State 模式**——如果分支取决于**对象当前状态**而不是消息类型：

```swift
// ❌ 把状态藏在 if 里
func tap() {
    if state == .idle { startRecording() }
    else if state == .recording { stopRecording() }
    else if state == .processing { showSpinner() }
}

// ✅ 状态机 / enum with associated value
enum RecorderState {
    case idle, recording(startTime: Date), processing
    func handleTap() -> RecorderState { ... }
}
```

**拆函数**——如果分支只是把多种独立行为塞进同一个名字下：

```swift
// ❌ 一个函数干 3 件事
func updateUI(showLoading: Bool, showError: Bool, hideAll: Bool) { ... }

// ✅ 三个函数
func showLoading() { ... }
func showError(_ err: Error) { ... }
func hideAll() { ... }
```

### 什么时候打补丁 OK（含技术债登记的具体姿势）

- **真的就 2 个分支**且不会再增长（`if isLoggedIn { ... } else { ... }` 是 OK 的）
- 任务范围明确说**只加这一个 case，重构属于另一个 task**——接受补丁，但**必须显式登记技术债**

「显式登记技术债」是这一档**最容易做错**的部分。多数 agent 会写：

```swift
// ❌ 反例：埋 TODO 当登记
} else if msg.isSkillEvent {
    // TODO: 后面用 Strategy 重构整个 send 函数
    // ...新增 25 行...
}
```

这等于**没登记**。统计上 80%+ 的 `TODO: 后面优化` 永远不会被处理——它们没 owner / 没 deadline / 没 acceptance criteria，没人订阅，CI 不会提醒，半年后还在原处。

**正例**——登记到能被订阅 / 能被关闭的载体：

```swift
// ✅ 选 1：commit message + ticket 联动（最稳）
} else if msg.isSkillEvent {
    // Tracked in TECH-DEBT-42: re-architect ChatMessageSender to Strategy
    // before adding the 5th message kind.
    // ...新增 25 行...
}
```

ticket 内容应当包含：
- 触发条件（「再加第 5 种 message kind 前必须做 enum + Strategy 重构」）
- 估时（重构成本 1-2h）
- 已积累的相关分支链接（point to 当前 PR + 之前 3 个 PR）

```markdown
# ✅ 选 2：项目根 docs/tech-debt.md（适合不想/不能用 ticket 系统）

## TD-2026-04: ChatMessageSender if/else 累积
- 触发：再加第 5 种 message kind 前必须重构
- 当前分支数：4 (system / error / skillEvent / normal)
- 重构方向：enum + Strategy（见 `references/gof.md` 第 1-2 节）
- 估时：1-2h
- 拥有者：@yangcan
```

```bash
# ✅ 选 3：PR 描述里点名（最低门槛，但易丢失）
PR description:
> ⚠️ Tech debt: this PR adds the 4th if/else branch in ChatMessageSender.
> Strategy refactor deferred. **Do not add a 5th branch without refactoring first.**
```

**正反对照**：

| 维度 | 埋 `TODO:` 注释（❌） | 登记 ticket / docs（✅） |
|---|---|---|
| 有 owner | 没 | 有 |
| 有 deadline / 触发条件 | 没 | 有 |
| 能被搜索 / 关闭 | 难 | 易 |
| Code review 可识别 | 看注释才发现 | PR 描述 / commit log 主动暴露 |
| 半年后是否还活着 | 80%+ 仍在 | 大概率已处理或主动 close 了 |

**Code review 角度**：看到代码里写 `// TODO: 之后重构` / `// FIXME` / `// 先这样` 这类注释**就要卡住**，要求作者把它升级成 ticket 或 `docs/tech-debt.md` 条目，PR 描述里留 link。这是 anti-patterns #4 的核心信号同款处理。

---

## 2. 复制粘贴后改变量名 / 不看调用链只改当前文件

### 触发信号

- 把别处一段 5-30 行代码 copy 到新文件，改了几个变量名 / 函数名就用
- 给一个 bug 加 fix，但**没 grep 这个函数 / 类型被多少地方调用**
- 同样的「权限 → 弹窗 → 处理结果」逻辑在 3 个业务模块里各写了一份
- 「我先在 A 文件改了，B 文件相同的代码先不动，反正功能 OK」
- 文件名带 `XxxV2` / `XxxNew` / `XxxCopy`

### 为什么是反模式

复制粘贴的代码会**独立漂移**——一份修了 bug，另一份没修；一份加了功能，另一份没加。半年后 3 份代码行为微妙不一致，谁都不敢动哪一份。

只改当前文件不看调用链，会**违反调用方的隐含契约**——你以为只改了 A，调用 A 的 B、C、D 全炸。

### 重构方向

**先 grep 看复用范围 / 调用链**：

```bash
# 改一个函数前先看谁在调
grep -rn "fooMethod" .
# 改一个类型前先看谁在用
grep -rn "FooManager\b" .
```

**同模块内**：抽函数 / 抽 helper

```swift
// ❌ 三个 VC 各写一份
class AVC { func handleTap() { /* 15 行权限 + 弹窗 */ } }
class BVC { func handleTap() { /* 15 行权限 + 弹窗，差一句话 */ } }
class CVC { func handleTap() { /* 15 行权限 + 弹窗，又差一句话 */ } }

// ✅ 抽到协议 / helper
protocol PermissionFlowHandler {
    var permissionType: Permission { get }
    func onGranted()
    func onDenied()
}
extension PermissionFlowHandler where Self: UIViewController {
    func runPermissionFlow() { ... }  // 统一实现
}
```

**跨模块**：下沉到共享层 / 走中间件（详见 SKILL.md §IV.4-5）

**复制粘贴是合理的**唯一情况：
- **测试代码** —— 测试有意冗余、明确性 > DRY
- **明确不会一起演化** —— 比如「示例代码」和「真实代码」长得像但生命周期完全独立

### 什么时候打补丁 OK

- 临时 spike / proof-of-concept，明确知道会扔掉
- 任务范围说「只在这一处修」，跨文件统一是另一个 task —— 同样**显式登记技术债**

---

## 3. 看现象不查根因（顶 try/catch / 顶 default 值）

### 触发信号

- 用 `try?` / `catch { }` 把 error 整个吞掉，没有日志、没有上报、没有降级路径
- 用 `?? defaultValue` 兜底但**没解释为什么 nil 是合法的**
- crash log 显示 `unwrap nil`，修复方式是「加个 `?` 安全 unwrap」就完事
- 「这里偶尔 crash，加个 if 判断防一下」
- bug 报告说「点这个按钮没反应」，修复 = 「加个 toast 告诉用户失败了」（用户可能根本不该到这一步）

### 为什么是反模式

- **症状消失 ≠ 问题修复**。Error 被吞掉 → 下次以另一种症状报上来（数据不一致 / 用户投诉 / 监控告警），定位成本指数级上升
- **隐藏的契约违反**会传染。函数 A 偶尔返回 nil，调用方 B 加 default 值 → 调用方 C 又加 fallback → 真实数据流在哪？没人知道
- **生产期才暴露**。Debug 模式下补丁让 bug 不可见，prod 环境下 edge case 一定会触发

### 重构方向

**5-Why 根因分析**：

```
现象：tap 按钮 crash on nil unwrap
Why 1: 因为 `viewModel.user!` 此刻是 nil
Why 2: 因为 viewDidLoad 里没等 user fetch 完成
Why 3: 因为 user fetch 是 async，但 UI 是 sync 渲染
Why 4: 因为登录态恢复路径下没 await user
Why 5: 因为 LaunchManager 里 user 不在 launch task 序列中

→ 根因在 LaunchManager 的启动顺序，不在 viewDidLoad
→ 修复：把 user fetch 放进 launch task；UI 在 viewDidLoad 时 user 已可用
→ 反模式修复：在 viewDidLoad 加 `if user == nil { return }` —— 治标不治本
```

**Error 是合法分支时**用 sum type / Result：

```swift
// ❌ 吞错
do { try await fetchUser() } catch { /* nothing */ }

// ✅ 显式分支
enum UserLoadResult { case success(User), notLoggedIn, networkFailed(Error) }
let result = await loadUser()
switch result {
case .success(let u): showProfile(u)
case .notLoggedIn: showLoginSheet()
case .networkFailed(let e): showRetryBanner(e); logger.error(...)
}
```

**Default 值要有解释**：

```swift
// ❌
let count = response?.items.count ?? 0  // 为什么 0？

// ✅
// 后端首次启动用户返回 nil（而不是空数组），按零条目处理
let count = response?.items.count ?? 0
```

### 什么时候打补丁 OK

- **降级路径明确**：「网络失败显示缓存」是合法降级，不是吞错
- **临时 hotfix** 解 prod 燃眉之急 → 同时**开 ticket 跟进根因**，hotfix commit 里 link 到 ticket

---

## 4. TODO 注释 / 「以后再优化」类遗留账

### 触发信号

- `// TODO: 之后用 Strategy 重构` / `// FIXME: 这里有 race condition`
- `// 先这样` / `// 临时方案` / `// 等 v2 再改`
- `// HACK:` / `// XXX:` 标记
- 注释提到「等 PR #123 合并后清理」，但 PR 已合并半年

### 为什么是反模式

- **TODO 在代码库里活得比作者还久**。统计上 80%+ 的 `TODO: 后面优化` 永远不会被处理
- **它们没有 owner / deadline / acceptance criteria**——埋在文件里没人订阅，CI 不会提醒
- **它们是「明知反设计」的自我认证**——写下 TODO 的同时，作者已经承认了当下方案不对，但选择不改

### 重构方向

二选一，**不要写 TODO 之后就走**：

**选 A：当下就修**

如果重构成本可控（< 当前 task 30% 时间），直接做。Senior 的判断不是「能不能做」，而是「现在做 vs 半年后做的成本差」——多数时候现在做更便宜。

**选 B：显式登记技术债**

不是写注释，是**进入跟踪系统**：

- GitHub issue / Linear ticket，标 `tech-debt` label
- 项目根 `.tech-debt.md` / `docs/tech-debt.md`
- Comment 里 link 到 ticket（而不是让 comment 自己当 ticket）

```swift
// ❌
func fetchData() {
    // TODO: 后面用 Combine 重写
    URLSession.shared.dataTask(...) { ... }
}

// ✅
func fetchData() {
    // Tracked in TECH-DEBT-42: migrate to Combine when stack-wide async story stabilizes
    URLSession.shared.dataTask(...) { ... }
}
```

或者——**让 comment 和 ticket 一对一**，TODO 死掉时 ticket 也关掉。

### 什么时候 TODO 注释 OK

- **代码里指向同一文件 / 同一函数的具体下一步**，且**本 PR / 下个 PR 内会处理**：
  ```swift
  // TODO(this PR): 等 schema 拍板再补 default 值
  ```
- **明确的占位符**，且 reviewer 知道会被替换：
  ```swift
  // PLACEHOLDER: replaced by codegen
  ```
- **link 到 ticket** 的引用注释（见上方「选 B」）

---

## 通用反模式检测自检 grep

定期跑一下，看自己 / 团队代码有没有积累：

```bash
# TODO / FIXME 占比
grep -rn "TODO\|FIXME\|HACK\|XXX" --include='*.swift' . | wc -l

# 吞错（catch 块为空）
grep -rn "catch.*{\s*}\|catch.*{\s*//.*}" --include='*.swift' .

# try? 大量出现 = 多数地方在吞错
grep -rn "try?" --include='*.swift' . | wc -l

# boolean flag 函数（≥3 个 Bool 参数 = 红旗）
grep -rEn "func\s+\w+\([^)]*Bool[^)]*Bool[^)]*Bool" --include='*.swift' .
```

数字本身没意义；**趋势**有意义——这一周比上一周多了 30 个 TODO？该停下来 review 设计了。
