# iOS 列表容器选型：重复同类条目默认虚拟化

iOS 端「重复的同类条目集合」（滚动列表 / 表格）一律默认用虚拟化容器：`UICollectionView` / `UITableView` / SwiftUI `List` / `LazyVStack`。**不要**用「数据现在有界 / 无界」来判断能不能用 `UIStackView`。

## 触发

写 / 重构 iOS list UI —— 任何会滚动的同类条目集合（feed / 列表 / 表格 / 分组列表）。

## 不触发

- cell 内部的多行组合 / tag-chip 流式排列 / 按钮组（容器嵌在已虚拟化的 cell 里）
- 字段或 section 固定的详情页 / 表单（重复的是异构 section、不是同类条目，整页可滚动也 OK）
- macOS（本规则只约束 iOS）

## 规则

- **重复同类条目集合 → 虚拟化容器**（collectionView / tableView / List / LazyVStack），默认就这么选、第一版就做
- **固定异构组合 → `UIStackView` / `ScrollView+VStack`**

判据是**形态**、不是数据量：重复同类 → 虚拟化；固定异构 → stack/VStack。

## 禁止

- ❌ 用 `UIStackView` 全量 `addArrangedSubview` 渲染滚动同类列表，再手动加 cap / collapse「为了渲染不卡」—— 这等于坐实了它该是列表容器（纯 IA 的 top-N 摘要预览除外）
- ❌ 用「现在数据不多 / 有界」论证 stackView —— 界会随需求漂移、client 代码不动就能从有界变无界，没人会回头重选容器

## 关联

- reviewer 的性能反模式检查（`~/.claude/commands/review.md` 正确性 reviewer 第 7 条 iOS 性能反模式，建议层 / 非阻断）按本规则 flag
