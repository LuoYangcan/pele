# Review binding（条件式验收）

`needs_independent_review` / `needs_ui_review` 命中且客观验证 PASS 后由 Root 全文读取本文件；普通任务不读。

## 候选身份与证据绑定

客观 receipt 只证明当前 Git-visible 源码。启动 verifier / UI reviewer 前，Root 还必须冻结本次验收上下文：

1. `source`：`validation-receipt.sh --repo "$repo" source-fingerprint` 的当前值；
2. `plan`：ExecPlan 的绝对路径、revision 与文件 SHA-256，或同一任务原生 Plan mode 最终 plan 的完整正文 SHA-256（host 提供稳定 item/turn ID 时一并记录；不提供时以正文 SHA-256 加 Root 自拟任务 slug 作为 identity）。若窄任务按入口路由直接实现而没有 Plan/ExecPlan，则把用户原始目标、已授权 scope/non-goals、验收标准组成 canonical intent 正文，连同 user-message/thread ID（host 提供时）和正文 SHA-256 作为 `plan=`；它只为 review 绑定既有意图，不新增 checkpoint 或计划文件；
3. `validation`：匹配 `source` 的 receipt 路径、文件 SHA-256、所需 check IDs/coverage，或无 receipt 时规范化后的命令、exit code、coverage 与其 SHA-256；
4. 语义验收额外冻结 `diff`：`base_ref` 到最终候选的 binary patch，以及当前 untracked product paths JSON manifest；两者放在 `.reviews/`，binding 含绝对路径和 SHA-256，verifier 按 manifest 读取当前 untracked 文件；
5. UI 额外冻结 `design`（immutable file/node/version；provider 无 version 时以冻结 reference/measurement/resource bundle digest 为真相源，review 期间不 live 取 mutable latest）、`cases`（精确步骤、strict/loose、容差）和 `build`（实际安装 `.app` 的绝对路径与 `artifact-digest`、bundle ID、scheme、configuration、destination/runtime，以及对应 build receipt/check）。

语义 snapshot 使用最终候选、排除验收临时目录：

```bash
~/.claude/scripts/review-input-snapshot.sh \
  --repo "$repo" "$base_ref" "<slug>"
```

把 helper 返回的 `base_commit + patch SHA-256 + untracked manifest SHA-256` 作为 `diff=` binding。冻结后若 source fingerprint 变化，重新生成 snapshot，不能只重算外层 fingerprint。

在传入的 repo/worktree 上调用 `validation-receipt.sh --repo "$repo" review-fingerprint semantic|ui ...`（helper 强制所需 key 并排序）：语义验收得到 `review_input_fingerprint`，UI 验收得到 `ui_review_input_fingerprint`。review 请求必须带完整 binding 和 fingerprint，输出必须原样回显。Root 在派发前和接收结果后各以当前候选重算一次；接收后的重算还须核对 snapshot 输出的 mtime/inode 清单（行格式 `mtime inode path`，路径在行尾、可含空格）与当前文件，漂移即按窗口内写入处理。源码、最终 plan、diff snapshot、设计工件、用例/严格度、build 或验证证据任一变化，相关 PASS 立即失效。

“重算”必须先从当前文件/工件/plan item 重新取得每个 SHA 或 stable ID，再调用 helper；禁止拿上一次的 binding 字符串只重跑外层 hash。

binding value 只放 canonical 单行 identity/digest，不内联 plan/cases 正文；完整正文和结构化用例作为 review 输入另附，binding 引用其 SHA-256。

review 运行期间冻结所有 source/plan/design writer；只允许 UI reviewer 写 `.reviews/` 证据。窗口内一旦观察到相关写入就丢弃结果并重新冻结输入，即使结束时 fingerprint 恢复成旧值也不能复用。

Codex verifier 在 `sandbox_mode=read-only` 下用 `review-fingerprint semantic` 自行重算。Claude 的 parent permission mode 可能覆盖 subagent mode，因此 Claude verifier 不获得 Bash/Edit/Write，只读预附 patch、untracked manifest 和当前文件；其防陈旧由 Root 的派发前/接收后双重 fingerprint 校验保证。

## 独立语义验收

`needs_independent_review=true` 时，在客观验证 PASS 后启动一个 fresh、read-only verifier。输入必须包含：repo/worktree、`base_ref`、用户需求与最终 Plan/ExecPlan/canonical intent、最终 changed paths、冻结 patch 与 untracked manifest、完整 `plan=`/`validation=`/`diff=` bindings、`review_input_fingerprint` 和匹配当前源码的验证证据。

verifier 不跑 lint/build/test、不改代码、不再调度其他 agent。普通任务不启动 verifier，也不叠加第二个语义 verifier。

blocking finding 的路由：Root 先核实 → 修复 → 重新运行全部失效验证 → 把原 finding ID/正文、前次 fingerprint 和新 bindings 交给同一 verifier 做一次 recheck；第二次仍无进展则停下与用户对齐。用户目标、authoritative plan 或相关设计输入变化时，旧 review 同样失效。

## UI 验收

`needs_ui_review=true` 时，只有实际可安装 `.app` 已按 `build=` 冻结后才调用 UI reviewer；“build PASS”本身不够。它只验 plan/设计要求对应的视觉和交互，不替代语义 verifier。若两个 gate 同时命中，可并行验收同一最终源码，但分别校验各自的 context fingerprint。strict Figma 工件若暴露新的行为、scope、架构或验收决策，先回到 DISCOVER/PLAN_READY 更新最终 plan，再实施；不能让设计工件静默取代旧 plan。
