# GoF 经典对象级模式速查

SKILL.md §III 决策表的延伸资料。**不要为了用模式而用模式**——这份速查是帮你把"症状"对到"候选模式"，最后一步选不选还是看具体场景。

每个模式格式统一：触发信号 / 最简骨架（Swift） / iOS 项目落点 / 不该用场景。

> Swift 是 protocol-oriented 语言，多数模式落地在 Swift 里都是「protocol + 多实现」，不需要把 Java GoF 那套完整搬进来。

---

## 1. Strategy（策略）

**触发信号**：同一个动作有多种可互换实现 / 有 if-else 链根据「类型」选不同行为 / 调用方关心做什么不关心怎么做。

**骨架**：

```swift
protocol MessageSender { func send(_ msg: Message) async throws }
struct UserMessageSender: MessageSender { ... }
struct SystemMessageSender: MessageSender { ... }

let sender: MessageSender = pickSender(for: msg)
try await sender.send(msg)
```

**iOS 落点**：网络请求 `Endpoint` protocol 多实现 / 权限流 (HealthKit/Notification/Camera 各自实现) / 单 cell 多种渲染样式

**不该用**：只有 2 个稳定不会增长的分支 / 各分支共享大量状态（应考虑 State）

---

## 2. State / 状态机

**触发信号**：同一对象当前状态决定行为 / 状态间有明确迁移规则 / 不同状态下"同一事件"反应完全不同。

**骨架**：

```swift
enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing
    case done(Result<URL, Error>)
}

struct RecorderViewModel {
    private(set) var state: RecorderState = .idle
    mutating func handle(_ event: Event) {
        switch (state, event) {
        case (.idle, .tap): state = .recording(startedAt: .now)
        case (.recording, .tap): state = .processing
        case (.processing, .didFinish(let url)): state = .done(.success(url))
        default: break  // 非法迁移直接忽略 / 报错
        }
    }
}
```

**iOS 落点**：录音 / 上传等多阶段流程 / Onboarding 步骤推进 / ChatSheet composer 模式切换

**不该用**：只有两个状态且无迁移规则（bool 够用）/ 状态空间巨大且组合自由（用结构化状态多个独立字段，不要硬塞一个枚举）

---

## 3. Factory（工厂）

**触发信号**：创建对象按条件选不同子类 / 创建逻辑复杂到不该写在调用方 / 调用方持有创建参数但不关心具体类型。

**骨架**：

```swift
enum SenderFactory {
    static func make(for msg: Message, deps: AppDependencies) -> MessageSender {
        switch msg.kind {
        case .user: return UserMessageSender(network: deps.network)
        case .system: return SystemMessageSender(logger: deps.logger)
        }
    }
}
```

**iOS 落点**：ViewController 装配 / API client 选择（不同 env / tenant）/ Composer 输入控件按 channel 类型切换

**不该用**：创建逻辑就是 `init` 一行（直接 `Foo()` 比 `FooFactory.make()` 短）/ 类型本身就一个

---

## 4. Abstract Factory（抽象工厂）

**触发信号**：要创建**一族相关对象**（按主题切换整套：light / dark；按平台切换：iOS / macOS；按租户切换：A 商家 / B 商家）/ 每族有自己的 button / label / cell / dialog 实现，调用方不能临时拼。

**骨架**：

```swift
protocol UIThemeFactory {
    func makeButton() -> UIButton
    func makeLabel() -> UILabel
    func makeAlertController(title: String, message: String) -> UIAlertController
}

struct LightThemeFactory: UIThemeFactory { /* 一套 light 实现 */ }
struct DarkThemeFactory: UIThemeFactory { /* 一套 dark 实现 */ }

let factory: UIThemeFactory = ColorScheme.current == .dark ? DarkThemeFactory() : LightThemeFactory()
let btn = factory.makeButton()
```

**iOS 落点**：跨主题 UI kit / 跨租户白标产品 / 跨平台 cross-cutting view kit（iOS vs macOS）

**不该用**：实际只切一两个组件（用 Strategy / Factory 单点）/ 整族对象差异其实只是颜色 / 字号（用 Theme token 不要用 Abstract Factory）

---

## 5. Builder

**触发信号**：构造参数 ≥5 个 + 多数可选 / 构造过程有顺序依赖 / 想要 fluent API（`.foo().bar().build()`）

**骨架**：

```swift
final class URLRequestBuilder {
    private var url: URL
    private var headers: [String: String] = [:]
    private var method: String = "GET"
    private var body: Data?

    init(url: URL) { self.url = url }
    func method(_ m: String) -> Self { method = m; return self }
    func header(_ k: String, _ v: String) -> Self { headers[k] = v; return self }
    func body(_ d: Data) -> Self { body = d; return self }
    func build() -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        headers.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        r.httpBody = body
        return r
    }
}

let req = URLRequestBuilder(url: u).method("POST").header("Auth", t).body(d).build()
```

**iOS 落点**：URLRequest 拼装 / Notification 内容拼装 / 复杂 attributed string 拼装

**不该用**：参数 ≤3 个（用普通 init + default value）/ Swift 已有 result builder（如 SwiftUI ViewBuilder）的场景

---

## 6. Observer / Pub-Sub

**触发信号**：一个事件多处响应（user logout → 清缓存 / 跳登录页 / 关 socket / 上报埋点）/ 来源和消费者生命周期解耦 / 跨模块通信但不想强耦合。

**骨架**（Swift 三种实现）：

```swift
// 1) Combine
let subject = PassthroughSubject<UserEvent, Never>()
subject.sink { event in /* react */ }.store(in: &cancellables)
subject.send(.loggedOut)

// 2) NotificationCenter（项目里有现成 Notification.Name 时）
NotificationCenter.default.post(name: .userDidLogOut, object: nil)
NotificationCenter.default.addObserver(forName: .userDidLogOut, ...) { _ in /* react */ }

// 3) closure callback（简单单点）
struct LoginManager { var onLogout: (() -> Void)? }
```

**iOS 落点**：登录态变更 / 主题切换 / 跨模块导航（业务模块通过 `Router.deeplink` 触发，不互相 import）

**不该用**：只有一对一通信（直接调用更短）/ 同步强依赖（caller 必须等 receiver 处理完）

---

## 7. Decorator

**触发信号**：想给对象**动态加能力**（log / 缓存 / 限流 / 权限校验 / 重试），而不改原对象 / 多个能力可叠加（log + cache + retry）。

**骨架**：

```swift
protocol UserService {
    func fetch(id: String) async throws -> User
}

struct RealUserService: UserService { /* 真网络调用 */ }

struct LoggingUserService: UserService {
    let inner: UserService
    func fetch(id: String) async throws -> User {
        logger.info("fetch user \(id)")
        defer { logger.info("fetch user done \(id)") }
        return try await inner.fetch(id: id)
    }
}

struct CachingUserService: UserService {
    let inner: UserService
    private var cache: [String: User] = [:]
    func fetch(id: String) async throws -> User {
        if let cached = cache[id] { return cached }
        let u = try await inner.fetch(id: id)
        cache[id] = u
        return u
    }
}

let service: UserService = CachingUserService(
    inner: LoggingUserService(inner: RealUserService())
)
```

**iOS 落点**：URL session interceptor / repository 加缓存层 / 给 request 加 auth header / SwiftUI ViewModifier

**不该用**：只有一种能力（直接写进原对象）/ 能力不能正交叠加（应该是 Strategy 不是 Decorator）

---

## 8. Adapter

**触发信号**：老 API 接口和新 API 不匹配 / 需要把第三方库的 API 适配成项目内部的 protocol / 多个不兼容的来源要喂给同一个消费者。

**骨架**：

```swift
// 项目内部 protocol
protocol ImageLoader {
    func load(_ url: URL) async throws -> UIImage
}

// 适配 Nuke
struct NukeImageLoaderAdapter: ImageLoader {
    let pipeline: ImagePipeline
    func load(_ url: URL) async throws -> UIImage {
        let response = try await pipeline.image(for: url)
        return response.image
    }
}

// 适配 Kingfisher
struct KingfisherAdapter: ImageLoader { ... }
```

**iOS 落点**：包装第三方 SDK（Nuke / Kingfisher / Alamofire）成项目内部 protocol / 适配 legacy ObjC API 给 Swift / 旧 NSError 适配成新 Result

**不该用**：能直接用第三方 API 且不会换实现（多此一举的间接层）/ 适配后接口跟原来一样（没真适配，是 Decorator）

---

## 9. Facade

**触发信号**：想给一组复杂子系统提供简单入口 / 调用方不该看到 N 个 service / manager 的细节 / 跨多个 service 协同的常见操作要简化。

**骨架**：

```swift
// 三个子系统
struct PaymentGateway { func charge(_ amount: Decimal) async throws { ... } }
struct InventoryService { func reserve(_ items: [Item]) async throws { ... } }
struct ShippingService { func schedule(for order: Order) async throws { ... } }

// Facade
final class CheckoutFacade {
    let payment: PaymentGateway
    let inventory: InventoryService
    let shipping: ShippingService

    func placeOrder(_ order: Order) async throws -> OrderConfirmation {
        try await inventory.reserve(order.items)
        try await payment.charge(order.total)
        try await shipping.schedule(for: order)
        return OrderConfirmation(...)
    }
}
```

**iOS 落点**：Onboarding flow（封装多步 API + UI 推进）/ 复杂启动序列（封装 LaunchManager 的 task 调度）/ 「分享」入口（封装多种平台的具体调用）

**不该用**：调用方实际需要细粒度控制（强行 facade 反而限制了灵活性）/ facade 内部只调一个子系统（多余的间接层）

---

## 10. Composite

**触发信号**：树形 / 嵌套结构 / 叶子和组合节点应有统一接口（FileSystem 里的 File 和 Folder 都能 `size()`）/ UI 层的组件嵌套（SwiftUI 已经天然是 Composite）。

**骨架**：

```swift
protocol Component {
    func render() -> String
    func size() -> Int
}

struct Leaf: Component {
    let name: String
    let bytes: Int
    func render() -> String { "📄 \(name) (\(bytes) bytes)" }
    func size() -> Int { bytes }
}

struct Composite: Component {
    let name: String
    let children: [Component]
    func render() -> String {
        "📁 \(name)\n" + children.map { "  " + $0.render() }.joined(separator: "\n")
    }
    func size() -> Int { children.reduce(0) { $0 + $1.size() } }
}
```

**iOS 落点**：嵌套菜单 / 文件系统 / 嵌套通知组 / 富文本 attributed 拼装。SwiftUI / UIKit view hierarchy 本身就是 Composite。

**不该用**：结构是平铺的不是树形 / 叶子和组合的接口语义差很多（强行统一会 throw 或返回无意义值）

---

## 11. Command

**触发信号**：想把"操作"做成一等公民（封装成对象）/ 需要 undo/redo / 需要排队 / 延迟 / 序列化执行。

**骨架**：

```swift
protocol Command {
    func execute() async throws
    func undo() async throws
}

struct DeleteMessageCommand: Command {
    let messageId: String
    let store: MessageStore
    private var deleted: Message?

    mutating func execute() async throws {
        deleted = try await store.delete(messageId)
    }
    func undo() async throws {
        if let m = deleted { try await store.insert(m) }
    }
}

final class CommandHistory {
    private var commands: [Command] = []
    func run(_ cmd: Command) async throws {
        try await cmd.execute()
        commands.append(cmd)
    }
    func undoLast() async throws {
        guard let cmd = commands.popLast() else { return }
        try await cmd.undo()
    }
}
```

**iOS 落点**：富文本编辑器的 undo/redo / drawing app / 离线消息队列 / 用户操作埋点序列

**不该用**：操作不需要回滚 / 操作不需要排队 / 单步 fire-and-forget（直接调函数）

---

## 12. Chain of Responsibility / Pipeline

**触发信号**：一个输入需要**多步串行处理**，每步独立 / 步骤可插拔 / 重排 / 跳过 / 中间任何一步可短路（命中后续步骤不再处理）。

**骨架**：

```swift
protocol RequestInterceptor {
    func intercept(
        _ req: URLRequest,
        next: (URLRequest) async throws -> Response
    ) async throws -> Response
}

struct AuthInterceptor: RequestInterceptor { ... }
struct LoggingInterceptor: RequestInterceptor { ... }
struct RetryInterceptor: RequestInterceptor { ... }

let chain: [RequestInterceptor] = [LoggingInterceptor(), AuthInterceptor(), RetryInterceptor()]
// 链式 invoke
```

**iOS 落点**：网络请求拦截器（auth / log / retry / cache）/ 消息发送前置处理（敏感词 / 附件压缩 / 签名）/ Onboarding 推进（每步独立 + 可跳过）

**不该用**：步骤不会变 / 不会重排（直接顺序调用更直白）/ 步骤之间紧耦合（B 必须用 A 的中间状态——其实是一个函数）

---

## 13. Visitor

**触发信号**：稳定的对象层级（class / enum case 不会频繁加）+ 经常给它们加新操作 / 需要多 dispatch（行为依赖**两个**对象的运行时类型）。

**骨架**：

```swift
indirect enum Expression {
    case number(Double)
    case add(Expression, Expression)
    case multiply(Expression, Expression)
}

protocol ExpressionVisitor {
    associatedtype R
    func visit(number n: Double) -> R
    func visit(add lhs: Expression, _ rhs: Expression) -> R
    func visit(multiply lhs: Expression, _ rhs: Expression) -> R
}

extension Expression {
    func accept<V: ExpressionVisitor>(_ v: V) -> V.R {
        switch self {
        case .number(let n): return v.visit(number: n)
        case .add(let l, let r): return v.visit(add: l, r)
        case .multiply(let l, let r): return v.visit(multiply: l, r)
        }
    }
}

struct EvalVisitor: ExpressionVisitor { /* 求值 */ }
struct PrintVisitor: ExpressionVisitor { /* 打印 */ }
```

**iOS 落点**：编译器 / DSL 解释器 / 文档导出（同一文档树导出 PDF / HTML / Markdown）

**不该用**：Swift 中绝大多数情况，**enum + switch 比 Visitor 直接 + 简单 + 编译期穷尽**。仅当对象层级稳定 + 操作频繁加 + 需要分离实现时才考虑。

---

## 14. Result / sum type

**触发信号**：错误是**业务上的合法分支**（用户没登录 / 网络无连接 / 缓存命中）/ 调用方需要穷举处理所有可能结果（编译器查漏）/ 不想用 throw（throw 在 actor / async 边界不友好）。

**骨架**：

```swift
enum LoadUserResult {
    case success(User)
    case notLoggedIn
    case networkFailed(Error)
    case rateLimited(retryAfter: TimeInterval)
}

func loadUser() async -> LoadUserResult { ... }

switch await loadUser() {
case .success(let u): showProfile(u)
case .notLoggedIn: showLoginSheet()
case .networkFailed(let e): showError(e)
case .rateLimited(let t): scheduleRetry(after: t)
}
```

**iOS 落点**：业务关心多种失败原因的 API / 权限请求结果（granted / denied / restricted / notDetermined）/ 缓存命中策略（freshHit / staleHit / miss）

**不该用**：只有 success / failure 两个结果（用 Swift 自带 `Result<T, Error>`）/ 错误真的是异常（assert / 程序员错误，用 `precondition` / `fatalError` / throw）

---

## 15. Composition over Inheritance + 中间件（依赖反转）

**触发信号**：想新建 class 继承 base class 只为加一个能力 / 多个不相关的 class 都需要同一个能力（埋点 / 日志 / 持久化）/ 跨模块复用受依赖方向限制（业务模块互相不能 import）。

**骨架**：

Protocol + 默认实现替代继承：

```swift
protocol Trackable { var tracker: Tracker { get } }
extension Trackable {
    func track(_ event: String) { tracker.send(event) }
}
class ProfileVC: UIViewController, Trackable { let tracker: Tracker = ... }
class SettingsVC: UIViewController, Trackable { let tracker: Tracker = ... }
```

中间件（依赖反转，跨模块复用受限时）：

```swift
// 底层 package 定义协议 + 默认 no-op
public protocol HealthKitService { func requestAuthorization() async throws }
public struct NoopHealthKitService: HealthKitService { ... }
public enum HealthKitRouter {
    public static var shared: HealthKitService = NoopHealthKitService()
}

// app 层启动时注入真实实现
HealthKitRouter.shared = RealHealthKitService()

// 业务层调用
try await HealthKitRouter.shared.requestAuthorization()
```

**iOS 落点**：跨业务模块服务调用（`TodayRouter` / `Router.register(serviceType:)`）/ View 能力混入（`Trackable` / `Themeable`）/ 测试替身（生产用真实，测试用 fake）

**不该用**：真的是 is-a 关系且只有单一继承层级（`UIButton: UIControl` 是 OK 的）/ 没有多个实现 / 没有测试需求

---

## Singleton — 警告，不是推荐

**触发信号（陷阱）**：「全局唯一」/「随处可访问」听起来美好。

**反对理由**：
- 隐式全局状态 → 并发地狱 / 测试困难 / 顺序依赖
- Swift 里 `Foo.shared` 多数时候**应该是 dependency injection**（构造时注入），不是全局
- 真正合理的 singleton 极少（系统资源代理如 `URLSession.shared`）

**只有**满足以下全部条件才考虑：
1. 这个对象封装的是**进程级唯一系统资源**（不是业务对象）
2. 没有任何理由需要 mock / 替换
3. 调用栈每个层级都需要它且改 init 注入成本极高

**多数情况**：用 DI（init 注入）/ 中间件（`Router.register`）/ environment object（SwiftUI）替代。

---

## 模式选择决策树（SKILL.md §III 表的速查版）

```
行为差异是什么决定的？
├─ 类型 / 调用方意图 → Strategy
├─ 对象自身状态 → State
├─ 创建条件（一个对象） → Factory
└─ 创建条件（一族对象） → Abstract Factory

是否一对多通信？
├─ 一对多 + 解耦 → Observer
└─ 一对一 → 直接调用

是不是多步独立处理？
├─ 是 + 顺序固定 → Pipeline
├─ 是 + 顺序可变 / 可短路 → Chain of Responsibility
└─ 否 → 单函数 / Strategy

错误是不是合法业务分支？
├─ 是 → Result / sum type
└─ 否 → throw / precondition

复用受依赖限制？
└─ 是 → 中间件 + 协议 + 默认实现

想给对象动态加能力？
├─ 单/多个能力可叠加 → Decorator
└─ 互斥能力 → Strategy

构造参数太多？
├─ ≥5 个 + 可选 → Builder
└─ ≤3 个 → 普通 init

操作要 undo/queue/log？
└─ 是 → Command
```

## 通用提醒

- **模式不是目的**：可读性 / 可维护性 / 可测试性是目的。模式让代码更短、调用方更直白、扩展更便宜——用；否则别用。
- **Swift 是 protocol-oriented**：多数模式落地都是「protocol + 多实现」，不需要 Java GoF 那套 abstract class 层级。
- **过早抽象比补丁更糟**：只看到 1 个 case 时不要预先建 Strategy；看到 2-3 个 case 再考虑。
- **模式经常组合**：Strategy + Factory（工厂返回不同策略）/ State + Observer（状态变化触发事件）/ Decorator + Strategy（不同策略上不同 decorator）—— 别拘泥单一模式。
