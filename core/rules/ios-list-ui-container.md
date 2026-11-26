---
paths:
  - "**/*.swift"
---

# iOS list container choice

A scrolling collection of homogeneous items (feed, list, table, sectioned list) defaults to a virtualized container: `UICollectionView` / `UITableView` / SwiftUI `List` / `LazyVStack`, in the first version. Detail pages and forms with fixed fields or sections, and the composition inside a cell, use `UIStackView` / `VStack`.

The criterion is shape, not data volume: do not argue for a stack view from "there is not much data now", and do not `addArrangedSubview` everything into a stack view and then add a cap / collapse to contain performance (a pure top-N summary preview is the exception).
