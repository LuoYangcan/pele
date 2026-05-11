# 系统架构（系统级 / 跨层边界）

UI 层架构（MVVM 等）讲的是**单个 feature / 页面**怎么组织。系统架构讲的是**整个 app / 整个 codebase 的边界怎么切** —— 业务核心 vs 副作用、内层 vs 外层、可测代码 vs 不可测代码。

覆盖：
- **Clean Architecture**（Robert Martin）
- **Hexagonal / Ports & Adapters**（Alistair Cockburn）
- **Functional Core Imperative Shell**（Gary Bernhardt）

> 某 iOS monorepo 项目的 `packages/common ↔ packages/ios/{Core,UI} ↔ packages/ios/Business` 单向分层就是 **Clean / Hexagonal 的工业级变体**——下面会专门对照。

---

## 速查决策表

| 你的现状 / 痛点 | 推荐 | 原因 |
|---|---|---|
| 业务逻辑跟 UIKit / SwiftUI 强耦合 / 难单测 | **Clean / Hexagonal** | 把核心业务放进**纯 Swift / 无 UI 依赖**的 inner layer |
| 多端共用业务（iOS + macOS / iPad+Phone） | **Clean / Hexagonal** | 业务核心跨平台共享 |
| 副作用（IO / 网络 / db / time）跟核心算法混在一起 | **Functional Core Imperative Shell** | 副作用集中到 shell，core 是 pure |
| 有大量第三方 SDK 想随时换（Firebase → 自家 / Nuke → Kingfisher） | **Hexagonal / Ports & Adapters** | SDK 是 adapter，业务核心不感知 |
| 业务逻辑频繁变化 / 高 churn / 需要 e2e 单测 | **Clean** + **Functional Core** 组合 | 双重防御 |
| 小型 app / 业务简单 / 团队 ≤ 3 人 | **不必上**，普通 MVC/MVVM 够 | 边界切得越细，沟通成本越高 |

---

## 1. Clean Architecture（Robert Martin）

### 核心：依赖方向单向、由外向内

```
┌────────────────────────────────────────────────┐
│  Frameworks & Drivers                          │  外层
│  (UIKit, SwiftUI, Network, DB, Firebase…)      │
│  ┌──────────────────────────────────────────┐  │
│  │  Interface Adapters                      │  │
│  │  (Presenters, Controllers, Gateways)     │  │
│  │  ┌────────────────────────────────────┐  │  │
│  │  │  Use Cases / Application Logic     │  │  │
│  │  │  (业务规则的"动作"层)              │  │  │
│  │  │  ┌──────────────────────────────┐  │  │  │
│  │  │  │  Entities                    │  │  │  │  内层
│  │  │  │  (核心业务对象 + 不变规则)   │  │  │  │
│  │  │  └──────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

**铁律**：**依赖箭头永远指向圆心**。外层知道内层，内层不知道外层。

- Entities 是**纯 Swift 类型**：`struct User`, `struct Order`，没有 UIKit / Foundation 之外的 import
- Use Cases 编排 Entity：`final class PlaceOrderUseCase`，构造时注入 protocol（不是具体实现）
- Interface Adapters 把外层数据转换成内层格式（response DTO ↔ Entity / persistence record ↔ Entity）
- Frameworks 是 UIKit / Combine / URLSession / CoreData——可以随时替换

### Swift 落地骨架

```swift
// Entities (无任何外部依赖)
struct Order {
    let id: String
    let items: [Item]
    var total: Decimal {
        items.reduce(.zero) { $0 + $1.price * Decimal($1.quantity) }
    }
}

// Use Case 输入端口（protocol）
protocol PlaceOrder {
    func execute(_ order: Order) async throws -> OrderConfirmation
}

// Use Case 实现 + 它的依赖也是 protocol
final class PlaceOrderUseCase: PlaceOrder {
    let payment: PaymentGateway   // protocol
    let inventory: Inventory      // protocol
    let notifier: OrderNotifier   // protocol

    func execute(_ order: Order) async throws -> OrderConfirmation {
        try await inventory.reserve(order.items)
        try await payment.charge(order.total)
        await notifier.send(.orderPlaced(order.id))
        return OrderConfirmation(orderId: order.id, total: order.total)
    }
}

// Interface Adapter：Presenter / ViewModel / Gateway
final class CheckoutViewModel {
    let placeOrder: PlaceOrder  // 依赖 use case，不依赖具体实现
    func tapPay() async { try await placeOrder.execute(...) }
}

// 外层：具体实现注入
let usecase = PlaceOrderUseCase(
    payment: StripePaymentAdapter(),
    inventory: SQLiteInventoryAdapter(),
    notifier: APNSNotifierAdapter()
)
let vm = CheckoutViewModel(placeOrder: usecase)
```

测试：
```swift
// 测 Use Case：mock 三个 protocol，零网络 / 零 UI
let mockPayment = MockPayment()
let mockInventory = MockInventory()
let usecase = PlaceOrderUseCase(payment: mockPayment, inventory: mockInventory, notifier: NoopNotifier())
let result = try await usecase.execute(testOrder)
```

### 何时用

- 业务复杂度 ≥ UI 复杂度（业务规则比按钮多）
- 多端复用业务（iOS + macOS / phone + tablet / app + extension）
- 需要全 use case 单测
- 大概率会换实现（DB / 第三方 SDK / 网络层）

### 何时不用

- App ≤ 5 屏幕 / 业务规则 ≤ 5 条（开销大于价值）
- 团队 ≤ 3 人（架构沟通成本压不下来）
- 业务规则简单、UI 复杂（PUI heavy app 用 MVVM 就够）

### 反例

```swift
// ❌ Use Case 引用了 UIKit
final class PlaceOrderUseCase {
    func execute(_ order: Order) async throws {
        let alert = UIAlertController(title: "Confirm?", ...)  // ← 内层引外层，违反铁律
        present(alert, ...)
    }
}

// ✅ Use Case 抛 confirmation needed，外层（VC）决定怎么显示
final class PlaceOrderUseCase {
    func execute(_ order: Order) async throws -> OrderConfirmation {
        // 业务规则在内层
    }
}
final class CheckoutVC: UIViewController {
    func tapPay() {
        present(UIAlertController(...))  // UI 在外层
    }
}
```

---

## 2. Hexagonal / Ports & Adapters（Alistair Cockburn）

### 核心：业务在中心，外面套一圈 ports

```
              ┌─────────────────┐
              │  HTTP Adapter   │
              │  (URLSession)   │
              └─────┬───────────┘
                    │ in port
                    ▼
       ┌──────────────────────────┐
       │                          │
       │      Application         │
       │      (Business Core)     │
       │                          │
       └──┬───────────────────┬───┘
          │ out port          │ out port
          ▼                   ▼
   ┌──────────┐         ┌──────────┐
   │ DB       │         │ Email    │
   │ Adapter  │         │ Adapter  │
   │ (Postgres)│         │ (SES)    │
   └──────────┘         └──────────┘
```

跟 Clean 的区别：
- **Clean** 关注**层数 / 内外**（Entity → Use Case → Adapter → Framework）
- **Hexagonal** 关注**入口 / 出口**对称（in port = 用户怎么进来；out port = 业务怎么找外部资源）

实践上很多人混用："Ports & Adapters" 就是 Clean 的轻量化表达。

### Swift 骨架

```swift
// Out port（业务调用外部能力的协议）
protocol UserRepository {
    func find(_ id: String) async throws -> User?
}
protocol Notifier {
    func send(_ msg: Message) async throws
}

// 业务核心（不依赖任何具体实现）
final class WelcomeNewUserService {
    let users: UserRepository
    let notifier: Notifier
    func welcome(_ userId: String) async throws {
        guard let user = try await users.find(userId) else { return }
        try await notifier.send(.welcome(user))
    }
}

// In port（外部进来的入口）
protocol WelcomeNewUserHandler {
    func handle(_ request: WelcomeRequest) async throws
}

extension WelcomeNewUserService: WelcomeNewUserHandler {
    func handle(_ request: WelcomeRequest) async throws {
        try await welcome(request.userId)
    }
}

// Adapters
struct CoreDataUserRepository: UserRepository { ... }
struct APNSNotifier: Notifier { ... }

// 测试时注入 mock
let svc = WelcomeNewUserService(
    users: InMemoryUserRepository(),
    notifier: SpyNotifier()
)
```

### 何时用

- 业务核心稳定，但依赖（DB / SDK / 通知）经常换
- 系统是 server-side（Vapor / Kitura）—— Hexagonal 在 server 端比 client 端更常见
- 需要插拔式 adapter（同一业务跑生产用 Postgres、跑测试用 InMemory、跑 staging 用 SQLite）

### 何时不用

- iOS / macOS app 业务简单（多数 client 应用）
- 没有多 adapter 切换需求

---

## 3. Functional Core Imperative Shell（Gary Bernhardt）

### 核心：Pure 业务逻辑 + Imperative 副作用外壳

```
┌─────────────────────────────────────────┐
│      Imperative Shell                   │
│  • IO（网络 / 文件 / DB）                │
│  • Time / 随机 / 状态                    │
│  • UI / 用户输入                         │
│  ┌───────────────────────────────────┐  │
│  │      Functional Core              │  │
│  │  • 纯函数 (input → output)        │  │
│  │  • 不可变数据                      │  │
│  │  • 业务规则 / 算法 / 计算          │  │
│  │  • 零副作用                        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**铁律**：core 里**只有 pure functions**，shell 拿着 core 的输出 + 触发副作用。

跟 Clean 的关系：Functional Core 是 Clean 内层的极致版——内层不只「不依赖外层」，还**完全没副作用**。

### Swift 落地

```swift
// Core: pure functions（业务规则）
struct Pricing {
    static func calculateTotal(items: [CartItem], coupons: [Coupon], taxRate: Double) -> PriceBreakdown {
        let subtotal = items.reduce(0) { $0 + $1.price * Double($1.quantity) }
        let discount = coupons.reduce(0) { $0 + $1.discount(for: subtotal) }
        let taxed = (subtotal - discount) * (1 + taxRate)
        return PriceBreakdown(subtotal: subtotal, discount: discount, total: taxed)
    }

    static func applyPromotion(state: CheckoutState, promotion: Promotion) -> CheckoutState {
        // 输入 state 不动，返回新 state
        var s = state
        s.activePromotions.append(promotion)
        s.totals = calculateTotal(items: s.items, coupons: s.activePromotions.map(\.coupon), taxRate: s.taxRate)
        return s
    }
}

// Shell: 副作用 + 协调
final class CheckoutController {
    private var state: CheckoutState
    private let api: CheckoutAPI

    func tapApplyCoupon(_ code: String) async {
        do {
            let promotion = try await api.fetchPromotion(code: code)  // 副作用 in shell
            state = Pricing.applyPromotion(state: state, promotion: promotion)  // 调 pure core
            updateUI()  // 副作用 in shell
        } catch {
            showError(error)
        }
    }
}
```

测试：
```swift
// Core 单测：100% 覆盖率轻松
let result = Pricing.calculateTotal(items: [...], coupons: [...], taxRate: 0.08)
#expect(result.total == 21.6)
```

### 何时用

- 业务核心是计算密集 / 规则复杂（pricing / 算法 / 配置生成 / 模拟器）
- 想要单测业务核心几乎零基础设施
- 团队接受不可变数据 + 函数式风格
- 跟 SwiftUI 配合好（`@Observable` shell + pure core）

### 何时不用

- 业务核心几乎全是 IO（CRUD app）—— core 没什么可放
- 团队不熟悉函数式 / 把 var 改 struct + immutable update 当负担
- App 是 thin client 形态（前端只渲染后端结果，业务在 server）

---

## 4. 项目对照：某 iOS monorepo 的分层

项目实际架构是 **Clean + Hexagonal 的工业级简化版**：

```
packages/common/*                                    ← Inner（业务核心 / 跨平台）
   • <CoreModule> / <FoundationModule> / <ModelModule>   - Entities + 共享业务规则
   • <NetworkingModule> / <AuthModule>                    - Out port 抽象
        ↑
packages/ios/{Core, UI, DebugPanelKit, ThirdPart}    ← 平台基础层
   • Adapters：包装 iOS SDK / 第三方 SDK
   • `<SystemToolsModule>` 是 HealthKit / Music / Calendar 这些 system port 的 adapter
        ↑
packages/ios/Business/*                              ← Outer（业务功能 + 接口适配）
   • <ChatModule> / <ProfileModule> / <DevicesModule> / <OnboardingModule>
   • Use cases + ViewModel + UI
```

依赖方向跟 Clean 完全一致：**外层依赖内层，内层不依赖外层**。Business 层不能互依（横向禁止），需要复用就**下沉**（拉到 Core / common）或**走中间件**（`Router.register` adapter 模式）。

`Router.register(serviceType:)` + protocol 暴露 + app 启动注入实现 = **Hexagonal Ports & Adapters 的教科书姿势**：
- Protocol（在 common 层）= out port
- 真实实现（在 app 层）= adapter
- 调用方（业务层）= 通过 port 间接拿 adapter，不知道具体实现

### 项目里你能说"我们用 Clean 吗"？

可以。但要补一句"**模块级 Clean，不是文件级 Clean**"——项目没强制每个 feature 写 Entity + UseCase + Adapter 的全套 5 件套。VC + ViewModel + Service 仍是常见 shape，只是包之间走 Clean 单向依赖。

---

## 选型决策树（系统层面）

```
是不是单端 client app 业务简单？
├─ 是 → 不必上 Clean / Hexagonal，分层用 MVVM 即可
└─ 否（业务复杂 / 多端 / 想换 SDK）
    ├─ 业务核心计算密集 / 算法多
    │   └─ Functional Core Imperative Shell
    ├─ 第三方 SDK 多 / 想插拔
    │   └─ Hexagonal / Ports & Adapters
    └─ 综合复杂（业务 + 多端 + SDK）
        └─ Clean Architecture（含 Use Cases 层）
```

## 反模式

- **Clean 但 Use Case 引 UIKit / Foundation Network**：Use Case 必须是纯业务，不能 import UIKit / URLSession（应通过 protocol 间接调用）
- **Hexagonal 但 adapter 反向调业务**：adapter 是被业务调用的（business → adapter via port），反过来就破坏了方向
- **Functional Core 但 core 内有 await / Date.now / random**：core 不允许这些；要么把这些数值通过参数传入，要么把它们移到 shell
- **小 app 上 Clean**：3 屏幕的 hobby app 套全套 5 件套，开发速度直接砍半，没好处
- **没有边界但喊"我们用 Clean"**：嘴上 Clean，代码上 VC 直接 import URLSession + import CoreData + import 第三方 SDK——这只是普通 MVC，不要装

## Why

系统架构的选择是**业务复杂度 + 测试需求 + 团队能力**的乘积。Clean / Hexagonal / Functional Core 都是给**业务复杂度 ≥ UI 复杂度**的项目用的——business heavy app（fintech / SaaS / 算法工具）才有真实回报。**UI heavy app**（chat / camera / 媒体）多数情况下分层简单的 MVVM 就够了。

不是越多边界越好——**每多一层边界 = 每多一处需要序列化 / 反序列化 / 转换的成本**。该上才上。
