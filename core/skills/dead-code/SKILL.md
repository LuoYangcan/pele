---
name: dead-code
description: Scan recent code changes for "zombie code" — newly-added or modified symbols that no caller references. Triggered by user invocation when an agent has been iterating heavily on the codebase and may have left orphan helpers, types, files, or enum cases behind. Scope defaults to `dev...HEAD` plus uncommitted changes (or `main...HEAD` — adapt to the project's main branch). Uses Periphery (preferred) and falls back to LSP `findReferences` + grep when Periphery is missing. Reports findings as a markdown table with confidence tiers and lets the user pick what to delete — never auto-deletes. Use when the user says "扫一下僵尸代码 / clean dead code / find unused / 检查是不是有没人调的方法 / 看看这次改动有没有遗弃代码", and especially after a generator subagent finishes a large iteration. Skip when there are no Swift changes in the current diff, or when the user is mid-implementation and explicitly said "稍后再清理".
---

# dead-code

Agent 反复迭代后，常常留下**僵尸代码**——存在于仓库里、却没有任何调用方的方法、类型、enum case、孤儿文件。这些代码编译能过、CI 也过，但是死的。本 skill 在用户显式调用时扫描**最近的改动**，把可疑的僵尸列出来让用户拍板，**绝不自动删除**。

> 当前实现仅支持 **Swift** 项目（依赖 [Periphery](https://github.com/peripheryapp/periphery) 的 SourceKit 索引）。其他语言生态可参考相同的「扫描 → 过滤到改动范围 → 分级 → 用户拍板」骨架，换底层工具（如 TypeScript: `ts-prune`、Python: `vulture`、Go: `unused`、Kotlin: `detekt --baseline` + `unused` rule）。
>
> 一个**例外角色 override**：当本 skill 由三段式调度的 `generator` subagent 在 review 前自动调用时（见 `agents/generator.md` Step 4.5），它可以在严格闸口下**自动删除本轮自己刚写出来的私域孤儿**。其他场景（用户显式调用 / `executor` 调用 / 手动跑）都遵守「报告 + 等用户挑」契约。

## 触发条件

**触发**（用户显式说）：

- 「扫一下僵尸代码」「清理一下没人用的方法」
- 「这次改动有没有遗弃代码」「dead code check」
- 「跑一下 dead-code skill」
- generator subagent 完事后，主 agent 想做一轮 cleanup
- PR 推之前想 self-review unused code

**不触发**：

- 当前 diff 里没有 Swift 文件改动（本 skill 只懂 Swift）
- 用户正在写代码中段，明确说「先放着，等做完再扫」
- 任务是修 lint / 修 typo / 改文案 —— 那种改动产不出僵尸

## 扫描范围

默认范围是**当前 worktree 的 `<main-branch>...HEAD` + 未提交改动**，用以下命令拼出来（按你项目主分支替换 `dev` / `main`）：

```bash
# base = merge-base 到 origin/<main-branch>（兜底到本地分支 / HEAD~1）
MAIN=dev   # 或 main / master，按项目实际改
BASE=$(git merge-base HEAD origin/$MAIN 2>/dev/null \
       || git merge-base HEAD $MAIN 2>/dev/null \
       || echo HEAD~1)

# 改动 / 新增的 Swift 文件
{
  git diff --name-only --diff-filter=AMR "$BASE" -- '*.swift'    # 已提交但还没 push 出去
  git diff --name-only -- '*.swift'                              # 未 staged
  git diff --name-only --cached -- '*.swift'                     # staged
  git ls-files --others --exclude-standard -- '*.swift'          # untracked 新文件
} | sort -u
```

如果用户**手动指定了范围**（"只看最近 3 个 commit" / "看 PR-123" / "整个 main"），按用户给的范围替换 `$BASE` 计算 diff —— 不要硬套默认值。

> ⚠️ **不扫主分支历史**：本 skill 设计用于「迭代中的工作」。如果用户问「整个项目有多少 dead code」，引导他直接跑 `periphery scan` 全量扫，不要走本 skill —— 全量结果太多、人工 review 不动。

## 前置：检测 Periphery

```bash
which periphery || echo "MISSING"
```

- **装了** → 走 [Periphery 路径](#path-a-periphery主路径)
- **没装** → 给用户两条建议（让他选）：
  1. 「我可以提示你装：`brew install periphery`，装完重跑本 skill」
  2. 「也可以走 LSP fallback 路径，慢一些、覆盖率低一些。要走 fallback 吗？」
  
  按用户回答动手。**不要**自己 `brew install`（全局副作用、需要授权）。

## Path A: Periphery（主路径）

### A.1 准备 Periphery 配置

如果项目里已有 `.periphery.yml`，直接用它；没有就生成一个临时配置（**Periphery ≥ 3.0 schema**）：

```bash
# Xcode workspace 的情况
cat > /tmp/periphery-deadcode.yml <<'EOF'
project: <YourApp>.xcworkspace                # 或 <YourApp>.xcodeproj
schemes:
  - <YourAppiOS>                              # 替换成实际 scheme（用 `xcodebuild -workspace ... -list` 看）
retain_public: true                           # 公开 API 跨包暴露，不能在本仓库判定无引用
retain_objc_accessible: true
retain_unused_protocol_func_params: true
EOF
```

> ⚠️ **3.x yml 字段重要变化**：`project:` 字段同时支持 `.xcworkspace` 和 `.xcodeproj`（不再有独立的 `workspace:` 字段）。`targets:` 字段已被移除，target 从 scheme 推导。如果你看到 `invalid key 'workspace'` 报错，就是版本对不上。

`retain_public: true` 是**关键**——多包 SPM 项目（典型如 `packages/common/*` + `packages/ios/{Core,UI,...}` + `packages/ios/Business/*` 这种分层结构）里大量 `public` 符号是给跨包用的，Periphery 在单 target 内当然找不到调用方，但它们不是僵尸。

如果项目是 SPM-only（没 xcworkspace），改成：

```yaml
project: Path/To/Package.swift
```

不确定 scheme 名 → 跑 `xcodebuild -workspace <YourApp>.xcworkspace -list | sed -n '/Schemes:/,$p' | head -30` 看一眼。

### A.2 跑扫描

```bash
periphery scan --config /tmp/periphery-deadcode.yml --format json > /tmp/periphery-output.json 2> /tmp/periphery-stderr.log
```

时间预期（典型多包 iOS app 实测）：

- **首次跑（无索引）**：5-10 分钟（Periphery 触发完整 SourceKit 索引）
- **后续跑（有 Xcode/Periphery 缓存）**：1-2 分钟
- **`--skip-build` 复用上次索引**：5-10 秒（适合短时间内连续重跑、临时改 yml 的场景）

```bash
# 如果你确定上一次 scan 之后没改过任何 Swift 文件，可以加 --skip-build 复用索引
periphery scan --config /tmp/periphery-deadcode.yml --format json --skip-build > /tmp/periphery-output.json 2> /tmp/periphery-stderr.log
```

build 失败时 Periphery 会在 stderr 报错——**不要** silent ignore，把 stderr 关键行展示给用户、问他是否需要先修 build。

### A.3 过滤到「最近改动」

Periphery 输出全量 unused 列表（项目老一点可能上百条），但本 skill 只关心**本轮改动产出的僵尸**。

#### A.3.1 JSON schema（实测于 Periphery 3.7.4）

每条记录长这样：

```json
{
  "location": "/abs/path/to/File.swift:15:1",
  "kind": "function.method.instance",
  "name": "suspend()",
  "hints": ["unused"],
  "accessibility": "internal",
  "modifiers": [],
  "attributes": [],
  "modules": ["<YourAppiOS>"],
  "ids": [...]
}
```

**关键字段**：

- `.location` 是**绝对路径** + `:line:col`（不是 relative！过滤时要么把 changed-files 转 absolute、要么用 endswith 模式匹配）
- `.kind` 是 dot-separated namespaced 字符串：`var.instance` / `var.static` / `var.parameter` / `function.method.instance` / `function.method.static` / `function.constructor` / `function.operator.infix` / `struct` / `class` / `enum` / `protocol` / `typealias` / `extension.struct` / `module`（`module` = unused import）
- `.hints` 是数组，常见值：`unused`（声明无人调用）、`assignOnlyProperty`（只赋值从未读）。两种都是僵尸候选
- `.accessibility` ∈ {`open`, `public`, `internal`, `fileprivate`, `private`}——配合「豁免清单」的 public 跨包判定使用

#### A.3.2 把 Periphery 结果交集到本轮改动

```bash
# 把 changed files 转 absolute path（Periphery location 是 absolute）
REPO=$(git rev-parse --show-toplevel)
sed "s|^|$REPO/|" /tmp/changed-files.txt > /tmp/changed-files-abs.txt

# 抽 Periphery 结果，按 absolute file 路径过滤
jq -r '.[] | "\(.location)\t\(.kind)\t\(.name)\t\(.accessibility)\t\(.hints | join(","))"' /tmp/periphery-output.json \
  | awk -F'\t' '
      NR==FNR { abs[$0]=1; next }
      {
        # location 形如 "/abs/path/File.swift:15:1"——按第一个 ":" 切出文件路径
        n = index($1, ":")
        file = substr($1, 1, n - 1)
        if (file in abs) print
      }
    ' /tmp/changed-files-abs.txt - \
  > /tmp/periphery-changed.tsv
```

**注意**：仅过滤到 changed files 还不够——如果一个旧文件里某个旧符号变成无人调用（被本轮 diff 删除调用方导致），这是僵尸但 Periphery 报告里仅显示该旧文件的某行，文件不在 changed-files 里。补一个第二轮过滤：

```bash
# 拿 changed files 里所有「被删除的」symbol references —— 这些可能让旧符号变成 unused
git diff "$BASE" -- '*.swift' | grep -E '^-' | grep -oE '\b[A-Z][A-Za-z0-9_]*\b|\b[a-z][A-Za-z0-9_]*\(' | sort -u > /tmp/possibly-orphaned-refs.txt

# Periphery 全量结果里 symbol name 命中以上的，也纳入候选
jq -r '.[] | "\(.location)\t\(.kind)\t\(.name)\t\(.accessibility)\t\(.hints | join(","))"' /tmp/periphery-output.json \
  | grep -F -f /tmp/possibly-orphaned-refs.txt \
  >> /tmp/periphery-changed.tsv
```

合并两份过滤结果、去重，得到**本轮改动相关的僵尸候选清单**。

### A.4 分级标注

把候选清单分成两档：

| 档位 | 含义 | 例子 |
|------|------|------|
| **High confidence** | 私有/internal symbol、声明在本轮改动里、Periphery + LSP findReferences 都说 0 ref | 新加的 `private func formatThing()` 没人调 |
| **Low confidence** | public symbol / @objc / 可能被 reflection 调用 / 在 protocol extension 里 / 被 @Test attribute / 是 SwiftUI `body`-only helper | `public func setupUI()` 在某个 VC 里没本仓库调用——但可能被 subclass override |

low-confidence 单独列出来，**不主动建议删**，仅供用户参考。

## Path B: LSP fallback（没 Periphery 时）

### B.1 抽取本轮改动新增的符号

```bash
git diff "$BASE" -- '*.swift' \
  | grep -E '^\+' \
  | grep -E '^\+\s*((public|internal|private|fileprivate|open)\s+)?(static\s+|class\s+|mutating\s+|final\s+)*(func|class|struct|enum|protocol|typealias|extension|case|var|let)\s+' \
  > /tmp/added-symbols.txt
```

正则抽出来的是**候选行**，需要进一步处理：

- 拿到 file:line（用 `git diff --unified=0` 对位拿行号，或直接 grep file 里这行的 line number）
- 拿到 symbol name（`func fooBar(...)` → `fooBar`）

### B.2 对每个候选符号跑 LSP findReferences

```text
LSP(operation="findReferences", filePath=<path>, line=<line>, character=<col>)
```

返回的 references 数量：

- **== 1**（只有声明自己） → high-confidence 僵尸
- **2~3 且都在同一文件** → low-confidence（可能只是 `private` 内部使用，但也可能是类内部的 placeholder）
- **>3 或跨文件** → 不是僵尸，跳过

### B.3 grep 二次验证

LSP 在以下场景会漏：协议默认实现、`@dynamicMemberLookup`、`@objc` 暴露、`#selector(...)` 引用、`String(describing:)` 反射。所以 high-confidence 候选**再 grep 一次符号名全词匹配**：

```bash
rg -n -w "<symbol>" --type swift
```

命中数 == 1（只有声明本身）才保留为 high-confidence；否则降级到 low-confidence。

> ⚠️ Path B 比 Path A 慢、覆盖度低，**不能**取代 Periphery。LSP 不懂 Swift 重载、不懂泛型派生、不懂 protocol witness——一个 false positive 让用户删了真正在用的代码就出大事。**Path B 的所有结论都建议用户人工核实**，不要给「直接删」的强建议。

## 豁免清单（不视为僵尸）

下列符号即使 0 ref 也**不要**算僵尸——把它们从结果里过滤掉：

| 模式 | 理由 |
|------|------|
| `public` 符号在 shared / common / 平台基础层 package（多包 SPM 项目里的 `packages/common/*`、`packages/ios/{Core,UI,...}` 这种分层） | 跨包暴露，单仓库判定不了 |
| 标了 `@objc` / `@objcMembers` / `@IBAction` / `@IBOutlet` | Obj-C runtime / IB 反射调用，静态分析看不到 |
| 在 `Tests/` / `*Tests/` 目录的 `@Test` / `func test...()` | 由 XCTest / Swift Testing runtime 反射拉起 |
| SwiftUI `#Preview { ... }` / `PreviewProvider` | Xcode preview 拉起 |
| `static func == / hash(into:) / func encode(to:) / init(from:)` | 协议 witness，static analysis 容易漏 |
| `deinit` / `init?(coder:)` | 系统反射调用 |
| extension 里实现了某 protocol 要求的方法（即使本类型没人调它） | protocol witness |
| 标了 `@available(*, deprecated)` | 已经在 deprecation 通道，本 skill 不重复 nag |

豁免规则**显式列在报告里**——让用户知道哪些符号被本 skill 跳过了，避免「我以为它会扫」的盲点。

## 输出报告（强制格式）

扫描完成后**必须**用这个 markdown 模板输出，让用户一眼看清：

```markdown
# Dead-code 扫描报告

**扫描范围**：`<base>...HEAD + 未提交`（共 N 个 Swift 文件改动）
**工具**：Periphery <version> / LSP fallback
**耗时**：约 X 分钟

## High confidence（建议删除，共 K 项）

| # | File | Line | Symbol | Kind | 判定理由 |
|---|------|------|--------|------|---------|
| 1 | `path/to/Foo.swift` | 42 | `formatThing` | private func | Periphery + LSP 0 ref，本轮新增 |
| 2 | ... | ... | ... | ... | ... |

## Low confidence（需人工核实，共 M 项）

| # | File | Line | Symbol | Kind | 判定理由 | 建议核实步骤 |
|---|------|------|--------|------|---------|------------|
| 1 | `path/to/Bar.swift` | 17 | `setupUI` | public func | public 符号、本仓库 0 ref | 全局 grep + 翻所有 import 本类的地方 |
| 2 | ... | ... | ... | ... | ... | ... |

## 豁免清单（共 P 项已跳过）

- `public` 跨包符号：N 项（在 shared / common 层 package）
- `@objc` 标记：N 项
- 测试 / Preview / 协议 witness：N 项

需要看豁免明细可以告诉我。

## 下一步

请挑：
- **(A) 我帮你删 high-confidence 全部 K 项** —— 我会用 Edit 工具把每个 symbol 删掉，并跑 build 确认编译通过
- **(B) 你点名删哪些** —— 列编号给我，比如「1, 3, 5」
- **(C) 仅给删除命令清单**，你自己手动改
- **(D) 全部不动**，先这样
```

> 报告里的判定理由要**具体**，比如「Periphery + LSP 0 ref，本轮新增」是好的；「unused」是没用的。

## 删除阶段（仅当用户选 A 或 B）

用户选 A / B 后：

1. 对每个要删的符号用 `Edit` 工具删除其声明（连带相邻的注释、空行清理）
2. 删完每改 3-5 个就跑一次项目的 build 命令（`just build-ios` / `xcodebuild` / `swift build` 等，按项目实际），**早发现编译错** —— 别一次删 20 个再 build，错了不知道是哪个删错了
3. 编译过了再继续；编译错了把那条改动 revert（用 git 或重新写回去），降级到 low-confidence 列表
4. 全部删完跑最终一次 build 确认整体绿
5. **不要 commit**——把 diff 留给用户审，commit 是用户的事

## 已知限制

- **Periphery 时间**：第一次扫 5-10 分钟（build + 索引）。后续命中缓存 1-2 分钟。`--skip-build` 复用上次索引可降到 5-10 秒（详见 A.2）。
- **跨语言桥接看不到**：Swift 调 C / C++ 的 bridging header、Swift 暴露给 Obj-C 的桥都可能被反射用。已经在豁免清单覆盖大部分，但不是 100%。
- **运行时 dynamic dispatch**：`#selector(target.action)`、KVO key path、`String(describing:)` 反射、`UIViewController.performSegue(withIdentifier:)` 这类，静态分析理论上看不到。**low-confidence 档位**就是给这些场景留的人工审核空间。
- **泛型 / 协议关联类型推导**：Periphery 偶尔误报某些泛型 helper。如果用户说「这个明明在用啊」，立即把它移到豁免说明里、不要硬辩。

## 这条 skill 不做的事

- ❌ **不自动 brew install Periphery** —— 全局副作用，让用户授权
- ❌ **不扫主分支历史** —— 设计用于迭代中工作；全量扫请直接跑 `periphery scan`
- ❌ **不自动 commit** —— 仅 Edit 文件，diff 留给用户审
- ❌ **不替代 SwiftLint / 项目级 lint** —— 那些查的是另一类问题（风格、复杂度），本 skill 只查「无人调用」
- ❌ **不替代 `/review`** —— `/review` 是综合 code review；本 skill 只看 dead code 这一维度
- ❌ **不删非 Swift 代码** —— 不扫 `.m` / `.mm` / `.cpp` / `.ts`；项目要扩到其他语言时单独写 skill
- ❌ **不在没拍板时改文件**（默认契约） —— 报告 + 等用户挑。**唯一例外**：generator subagent 在 review 前自动调用本 skill（见 `agents/generator.md` Step 4.5），可在严格闸口下自动删本轮自产的私域孤儿

## 与其他 skill / rule 的关系

- **`reuse-first` skill**：`reuse-first` 管事**前**预防（别造重复轮子）；本 skill 管事**后**清理（已经造出来的孤儿砍掉）。两条正交、不冲突。
- **内置 `simplify` skill**：`simplify`（Claude Code 内置）改完代码后跑 review subagent 自动 fix；本 skill 是单维度（unused），且**不自动 fix**（generator override 例外见上）。可以串行用：`simplify` 跑完后再跑本 skill 做最后一轮 cleanup。
- **`dispatch-pipeline` rule**：`generator` Step 4.5 在 review 前自动调本 skill 做自检；主 agent 阶段 2.5 review-fix 循环里也可以让用户选「再跑一轮 dead-code 扫描」作为 review 的一种形式。
- **`post-change-verify` rule**：本 skill 的删除阶段会跑 build —— 这是 post-change-verify 的一个具体应用（只跑编译、不主动跑 lint / test / format-fix）。

## Why

Agent 频繁迭代时，最容易留三类垃圾：

1. **方法被新方法替代了，旧方法没删** —— 比如改名后忘了删旧的
2. **写到一半换思路，半成品没拆** —— extension 里加了几个 helper，最后没用上
3. **整个文件孤立** —— 复制粘贴一份模板文件，最后没接进 target

人眼审 PR 时这些都能看出来，但 agent 的 PR 通常一次改十几个文件，diff 太长容易漏。本 skill 把「找无人调用」自动化、剥离掉**非僵尸**的噪声（public API、@objc、测试）、把判定证据呈给人，**让人做最后决定**。

定位是「轻量自动化 + 人审拍板」——比让 agent 自动删可靠（agent 看不到运行时反射），比纯人工 review 高效（人不会有耐心扫 50 个 file）。
