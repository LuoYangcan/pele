# UI 层架构选型

把"View Controller / Activity / Page 该长什么样、状态放哪、副作用怎么处理"展开。覆盖**经典层架构**（MVC / MVP / MVVM / VIPER）+ **单向数据流**（Redux / TCA / Elm / Reducer）。每个：核心思想 / 适用规模 / iOS 落地 / 何时不用 / 反例。

> 某 iOS monorepo 项目的 ChatVC 范式（UIKit + extension 切片 + `FooState.swift` + `FooViewModel.swift`）是 **MVVM 的轻量变体**——下面会专门对照说。

---

## 速查决策表

| 你的现状 | 推荐 | 不推荐 | 原因 |
|---|---|---|---|
| App ≤ 5 个屏幕 / hobby / 内部工具 | **MVC**（Apple 默认） | MVVM / VIPER 过度工程 | 简单足够 |
| 中型 app / VC 1000+ 行 / 想做单测 | **MVVM**（VC + ViewModel + State） | VIPER 太重 | 测试性 + VC 瘦身 |
| ViewModel 还是膨胀 / 协作团队 ≥ 4 人 / 需要明确边界 | **VIPER** 或 **MVVM-C**（加 Coordinator） | TCA 学习成本太高 | 进一步拆分职责 |
| state 散落各处 / 多源真相 / 难以追踪状态变更 | **单向数据流**（TCA / Reducer） | MVVM | 单一 state 树 + 显式 action |
| SwiftUI + state 复杂 + 团队接受函数式风格 | **TCA** 或 **Reducer + ObservableObject** | UIKit MVVM | SwiftUI 天然更适合单向流 |
| 需求未稳定 / 早期探索 | **MVC** 起步，遇到痛点再升级 | 一上来就 VIPER | 避免预先抽象 |

---

## 1. MVC（Model-View-Controller）

### 核心

- **Model**：数据 + 业务规则
- **View**：呈现
- **Controller**：协调，处理 user input / 更新 view

iOS 上 Apple 默认就是 MVC。`UIViewController` 既是 controller 也常常承担一部分 view 职责（"Massive ViewController"）。

### 何时用

- App 规模小（≤5-10 个屏幕）
- 没有大量异步 / 状态机 / 复杂表单
- 单人 / 小团队 / 快速 prototype
- Apple 标准 SDK 案例（多数 sample code 都是 MVC）

### 何时不用

- VC 已经超过 500 行
- 同一个 VC 处理了 view 装配 + 网络 + 数据转换 + state 管理（这就是 Massive VC）
- 需要单测业务逻辑（VC 跟 UIKit 强耦合，难单测）

### 反例

```swift
// ❌ Massive VC：1500 行 / 多职责混杂
class FeedVC: UIViewController {
    var posts: [Post] = []  // 数据
    var isLoading = false   // state
    var page = 0            // 翻页 cursor
    var filter: Filter?     // 业务规则
    func viewDidLoad() {
        // 装 view
        // 拉数据
        // 转换 model
        // 处理空态 / 错误 / 加载态
        // 翻页 / 下拉 / pull to refresh
        // 埋点
    }
}
```

→ 升级到 MVVM。

---

## 2. MVP（Model-View-Presenter）

### 核心

- **Model**：数据
- **View**：被动，只负责呈现 + 把事件转发给 Presenter
- **Presenter**：持有 view 引用，调 view.update(...)，处理逻辑

跟 MVC 的差别：Presenter 比 Controller 更被动 / 更可测——View 是 protocol（`PresenterDelegate`），Presenter 不引用 UIKit。

### 骨架

```swift
protocol FeedView: AnyObject {
    func showPosts(_ posts: [Post])
    func showLoading(_ loading: Bool)
    func showError(_ error: Error)
}

final class FeedPresenter {
    weak var view: FeedView?
    let api: FeedAPI

    func loadFirstPage() {
        view?.showLoading(true)
        Task {
            do {
                let posts = try await api.fetchFeed(page: 0)
                view?.showPosts(posts)
            } catch {
                view?.showError(error)
            }
            view?.showLoading(false)
        }
    }
}

class FeedVC: UIViewController, FeedView {
    let presenter: FeedPresenter
    func showPosts(_ posts: [Post]) { /* 更新 cell */ }
    func showLoading(_ loading: Bool) { /* 转圈 */ }
    func showError(_ error: Error) { /* alert */ }
}
```

### 何时用

- 有 Android 经验团队（MVP 在 Android 主流）
- 需要单测 Presenter（mock View protocol）
- VC 比较薄但又不愿引入 binding 框架（不用 Combine / RxSwift）

### 何时不用

- iOS 团队（MVVM 在 iOS 更主流）
- Presenter 持有 weak view 引用，多次 view 重建会 retain 周期混乱

### 现状

iOS 圈现在很少用 MVP，多数等价情况用 MVVM 替代。

---

## 3. MVVM（Model-View-ViewModel）

### 核心

- **Model**：数据 + 业务规则
- **View**（含 VC）：呈现 + 用户输入 → 转发给 ViewModel
- **ViewModel**：UI 状态 + 业务逻辑入口；**不引用 UIKit**，可单测

view 通过 binding（Combine / Observable / 手动 callback）订阅 ViewModel state。

### 骨架（某 iOS monorepo 的 ChatVC 范式）

```swift
// FooState.swift —— 跨方法边界的可变状态
struct FooState {
    var posts: [Post] = []
    var isLoading: Bool = false
    var page: Int = 0
    var filter: Filter?
}

// FooViewModel.swift —— 纯逻辑、可单测
final class FooViewModel {
    private(set) var state: FooState
    private let api: FeedAPI
    var onStateChange: ((FooState) -> Void)?

    func loadNextPage() async {
        state.isLoading = true; onStateChange?(state)
        do {
            let new = try await api.fetchFeed(page: state.page + 1)
            state.posts.append(contentsOf: new)
            state.page += 1
        } catch {
            // 错误处理
        }
        state.isLoading = false; onStateChange?(state)
    }
}

// FooVC.swift —— lifecycle / view 装配 / 注入
class FooVC: UIViewController {
    let viewModel: FooViewModel
    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
    }
    func render(_ state: FooState) {
        // 把 state → view 更新
    }
}

// FooViewController+Layout.swift / +Delegate.swift / +Backend.swift —— 切片
```

### 何时用

- 中型 app（VC 1000+ 行的迹象）
- 想单测业务逻辑（ViewModel 不引用 UIKit）
- 团队有 Swift / Combine / RxSwift / SwiftUI 经验
- **多数中型 iOS 项目的默认推荐**

### 何时不用

- 小型 app（MVC 够用）
- 状态散落到多个 ViewModel，需要协调（升级到 VIPER 或 单向数据流）
- 跨多 VC 共享 state（ViewModel 不擅长跨 VC 通信）

### 项目对照

某 iOS monorepo 的 ChatVC 范式（项目 `AGENTS.md` "ViewController 文件拆分约定"）就是 MVVM 的轻量变体：

- `FooViewController.swift` — VC 主文件（lifecycle）
- `FooViewController+<Aspect>.swift` — extension 切片（Layout / Backend / Composer / Delegate / Keyboard / LongPress）
- `FooState.swift` — UI / 行为状态（跨方法边界的 var）
- `FooViewModel.swift` — 纯逻辑 / 可测的 derive
- `FooViewModelTests.swift` — Swift Testing 单测

差别：项目用 extension 切片代替了「UIView 子类」。这是**针对 UIKit + 大型 VC** 的实用变体。

### 反例

```swift
// ❌ ViewModel 引用 UIKit
final class FeedViewModel {
    weak var tableView: UITableView?
    func reload() { tableView?.reloadData() }  // ← 不能单测了
}

// ✅ 通过 callback 让 view 自己 reload
final class FeedViewModel {
    var onPostsChanged: (([Post]) -> Void)?
    func loadFirstPage() async {
        let posts = try await ...
        onPostsChanged?(posts)
    }
}
```

---

## 4. VIPER

### 核心 5 件套

- **View**：呈现
- **Interactor**：业务逻辑 + 数据获取
- **Presenter**：协调 view 和 interactor
- **Entity**：数据 model
- **Router** / Wireframe：导航

每个屏幕一组 5 个文件 / 类。强分层 / 强职责切分。

### 何时用

- 大型 app（50+ 屏幕）
- 大团队（10+ 人）
- 严格的代码 review / 职责边界
- 有专人写 module、横向并行开发

### 何时不用

- 小 / 中型 app（VIPER 套全套：每个屏幕 5 个文件，仪式感大于价值）
- 团队 ≤5 人（沟通成本压不下来）
- 需求快速迭代（VIPER 改一个屏幕动 5 个文件，慢）

### 反例

```
// ❌ 给一个 detail screen 套 VIPER
DetailModule/
├── DetailViewController.swift
├── DetailView.swift
├── DetailPresenter.swift
├── DetailInteractor.swift
├── DetailEntity.swift
├── DetailRouter.swift
├── DetailContracts.swift
└── DetailBuilder.swift
```

实际上这个屏幕一共 80 行业务逻辑。MVVM 200 行一文件搞定。

### 现状

iOS 圈用 VIPER 的越来越少，多数转向 **MVVM + Coordinator** 或 **TCA**——VIPER 的 Router 和 Interactor 边界其实更适合用 Coordinator + Service / Repository 替代。

---

## 5. 单向数据流总览（Unidirectional Data Flow）

跟前面 4 个的根本区别：**state 是只读的 + 所有变更走显式 action + reducer 是 pure function**。

```
                ┌─→ View ──user action──→ Action ──→
                │                                    │
              State                                  ↓
                │                                  Reducer
                │←── Effect ←── EffectsRunner  ←──  │
                │                                    │
                └─── new State ←──────────────────  ┘
```

核心理念：**没有 setter 散落各处。要改 state 就 dispatch 一个 action，reducer 是唯一改 state 的地方**。

变种（按发明顺序）：
- **Elm**（2012, 函数式语言）—— 范式起点
- **Redux**（2015, JS）—— 把 Elm 模式带进 React
- **TCA / The Composable Architecture**（2020, Swift）—— Pointfree 团队的 Swift 实现
- **Reducer + ObservableObject**（2023+, SwiftUI）—— Apple 在 SwiftUI 提供的轻量化实现

---

## 5a. Redux（JS 范式，iOS 上较少直接用）

```swift
struct AppState {
    var user: User?
    var posts: [Post]
}

enum Action {
    case userLoggedIn(User)
    case postsLoaded([Post])
    case postLiked(id: String)
}

func reducer(_ state: AppState, _ action: Action) -> AppState {
    var s = state
    switch action {
    case .userLoggedIn(let u): s.user = u
    case .postsLoaded(let p): s.posts = p
    case .postLiked(let id):
        if let i = s.posts.firstIndex(where: { $0.id == id }) {
            s.posts[i].likeCount += 1
        }
    }
    return s
}

final class Store {
    private(set) var state: AppState
    func dispatch(_ a: Action) { state = reducer(state, a) }
}
```

**问题**：纯 reducer 做不了副作用（API call）。Redux 在 JS 里靠 middleware（thunk / saga / observable）补；iOS 上同样要补一层。

---

## 5b. TCA（The Composable Architecture）

iOS / SwiftUI 上的工业级实现。Pointfree 团队维护。

**核心组件**：

```swift
@Reducer
struct FeedFeature {
    @ObservableState
    struct State: Equatable {
        var posts: [Post] = []
        var isLoading = false
        var page = 0
    }

    enum Action {
        case loadFirstPage
        case loadFirstPageResponse(Result<[Post], Error>)
        case postLiked(id: String)
    }

    @Dependency(\.feedAPI) var api

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadFirstPage:
                state.isLoading = true
                return .run { send in
                    let result = await Result { try await api.fetchFeed(page: 0) }
                    await send(.loadFirstPageResponse(result))
                }
            case .loadFirstPageResponse(.success(let posts)):
                state.posts = posts
                state.isLoading = false
                return .none
            case .loadFirstPageResponse(.failure):
                state.isLoading = false
                return .none
            case .postLiked(let id):
                if let i = state.posts.firstIndex(where: { $0.id == id }) {
                    state.posts[i].likeCount += 1
                }
                return .none
            }
        }
    }
}

struct FeedView: View {
    @Bindable var store: StoreOf<FeedFeature>
    var body: some View {
        List(store.posts) { post in /* row */ }
        .task { store.send(.loadFirstPage) }
    }
}
```

**核心机制**：
- `Reducer` 是 pure function（state, action) → (state, effect)
- `Effect` 是显式表达「需要做的副作用」（网络 / 定时器 / sub），由 runtime 调度
- `@Dependency` 是 DI 的一等公民，测试时直接 swap
- Feature 可组合（`Scope` / `forEach`）

### 何时用

- SwiftUI app（TCA 跟 SwiftUI 天然贴合）
- 复杂 state（多源真相、状态机、撤销/重做）
- 团队接受函数式 / 严格不可变 state 的开销
- 想要全栈测试（reducer 是 pure，单测最便宜）

### 何时不用

- UIKit（TCA 也能用但冲突感强）
- 团队没接触过函数式 / 没看过 docs
- 简单 app（用 SwiftUI `@State` / `@Observable` 够用）
- 学习曲线陡（reducer / effect / dependency / store / scoping 全套概念）

---

## 5c. Elm

`Elm` 本身是一种函数式语言，提供 The Elm Architecture：

```
type Msg = Increment | Decrement
type alias Model = Int

update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment -> model + 1
        Decrement -> model - 1

view : Model -> Html Msg
view model = ...
```

iOS / Swift 上没有 Elm 直接对应，但 TCA / Redux 都是 Elm 的派生。iOS 实际项目里**不会直接用 Elm**，了解概念对学 TCA 有帮助。

---

## 5d. Reducer 模式（SwiftUI 轻量化）

不引入 TCA，用 SwiftUI 自己的工具实现简化版单向流：

```swift
@Observable
final class FeedStore {
    private(set) var state: FeedState = .init()
    private let api: FeedAPI

    enum Action {
        case loadFirstPage
        case postLiked(id: String)
    }

    func send(_ action: Action) {
        state = reduce(state, action)
        runEffects(for: action)
    }

    private func reduce(_ state: FeedState, _ action: Action) -> FeedState {
        var s = state
        switch action {
        case .loadFirstPage: s.isLoading = true
        case .postLiked(let id): /* mutate */ break
        }
        return s
    }

    private func runEffects(for action: Action) {
        switch action {
        case .loadFirstPage:
            Task {
                let posts = try await api.fetchFeed(page: 0)
                state.posts = posts
                state.isLoading = false
            }
        default: break
        }
    }
}

struct FeedView: View {
    @State private var store = FeedStore()
    var body: some View {
        List(store.state.posts) { post in /* row */ }
            .task { store.send(.loadFirstPage) }
    }
}
```

适合：SwiftUI app + 想要单向流但不想上 TCA 全套

---

## 6. MVVM-C（MVVM + Coordinator）

MVVM 的扩展。**Coordinator** 负责导航 / 跨屏幕协调：

```swift
final class FeedCoordinator {
    let nav: UINavigationController
    let api: FeedAPI

    func start() {
        let vm = FeedViewModel(api: api)
        let vc = FeedVC(viewModel: vm)
        vm.onPostTapped = { [weak self] post in
            self?.showDetail(for: post)
        }
        nav.pushViewController(vc, animated: false)
    }

    func showDetail(for post: Post) {
        let coord = PostDetailCoordinator(nav: nav, post: post)
        coord.start()
    }
}
```

VC 不直接 `pushViewController`，让 Coordinator 决定下一步。

### 何时用

- VC 之间有复杂导航（条件跳转 / 模态 / 多入口）
- 一个流程涉及多个屏幕（onboarding 9 步 / 支付 5 步）
- 想单测导航逻辑

### 项目对照

某 iOS monorepo 的 `<MyAppRouter>` + `Router.register` + deeplink 路由就是 **Coordinator 的工业级变体**——Router 模块化、跨业务包通信、deeplink 注册。比 hand-rolled Coordinator 更适合多模块项目。

---

## 选型决策树（项目角度）

```
project size?
├─ small (< 5 screens)
│   └─ MVC
└─ medium / large
    ├─ UIKit?
    │   ├─ small team / fast iteration
    │   │   └─ MVVM (monorepo 案例：ChatVC 范式)
    │   ├─ large team / strict boundaries
    │   │   └─ MVVM + Coordinator (monorepo 案例：&lt;MyAppRouter&gt;)
    │   └─ rigid module boundaries / 50+ screens / 10+ devs
    │       └─ VIPER (rare in modern iOS)
    └─ SwiftUI?
        ├─ simple state
        │   └─ @State / @Observable
        ├─ complex state + want pure reducers
        │   └─ Reducer pattern (轻量 TCA-style)
        └─ very complex / multi-feature / want test rig
            └─ TCA
```

## 反模式（UI 层常见）

- **Massive ViewController**：VC 1500+ 行，view + business + network 全在一处 → 升级到 MVVM
- **Anemic ViewModel**：VM 只是个 struct，没业务逻辑 → 业务逻辑跑哪儿去了？多半还在 VC，没真正 MVVM
- **God Coordinator**：一个 Coordinator 管整个 app 所有跳转 → 拆按 feature 切多个 Coordinator
- **TCA 中混入命令式 mutation**：reducer 里写 `state.x = await api.fetch(...)` → reducer 必须 pure，把 await 移到 `Effect`
- **Redux 但没 single source of truth**：还是 N 个 store / state 散落 → Redux 的核心就是 single source；做不到就用 MVVM
- **VIPER 做小项目**：每个 screen 5-8 个文件，业务逻辑 80 行 → 用 MVC / MVVM

## Why

UI 架构的选择是**项目规模 + 团队 + 测试需求**的乘积。没有"最好的架构"——**MVC 在小项目上比 TCA 健康得多**，**TCA 在大型 SwiftUI 上比 MVC 健康得多**。

听到「我们项目很大要用 VIPER」/「我们用 TCA 因为最先进」——都先问一句「你们的实际症状是什么？」**症状驱动选型**比信仰驱动更靠谱。
