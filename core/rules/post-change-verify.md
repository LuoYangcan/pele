# 最终候选验证

代码和必要项目文档稳定后，对最终源码只跑一轮覆盖本次改动的客观验证。执行者是 Root；长命令或长日志可交给 `command-runner`（host 无此 agent 时由 Root 直接执行），无需另起独立验证角色。

## 顺序

1. 运行项目已有的 cheap lint/check；没有则记录 `not configured`。
2. 运行覆盖生产入口的 build。
3. 用户要求、最终 plan 指定、已有测试直接覆盖改动，或高风险 gate 命中时，运行最窄的 relevant tests。
4. Simulator、真机、全量测试、formatter fix、Periphery 只在用户或对应 skill 触发时运行。

项目规则明确规定更强验证时服从项目规则。某个 targeted test 已完整编译同一生产 target 时，可说明覆盖关系并跳过重复 build；拿不准则仍跑 build。

## Receipt

单 Root、单 worktree、且验证结果不需要被 review gate、并行 fan-in 或跨 session 复用时，直接运行命令即可，不写 receipt。需要跨阶段复用验证结果时，用：

```bash
verify="$HOME/.claude/scripts/validation-receipt.sh"
repo="$(git rev-parse --show-toplevel)"
receipt="$repo/.specs/<slug>-validation.json"
"$verify" --repo "$repo" reusable "$receipt" <check-id> <coverage> || \
  "$verify" --repo "$repo" run "$receipt" <check-id> <coverage> -- <command> [args...]
```

receipt 只对当前 Git-visible 源码 fingerprint 有效；源码或项目文档变化后重新检查。helper 比较命令前后 fingerprint；检查过程改动 source 时写入 `invalidated` 并失败，不能把 post-state 记为 PASS。`.specs/` 与 `.reviews/` 临时工件本身不使源码 receipt 失效。

receipt 不能单独证明语义或 UI 验收仍有效。启动 verifier / UI reviewer 时按 `plan-first-delivery` 把 source fingerprint、authoritative plan、receipt/check evidence、语义 review 的 diff snapshot，以及 UI 所需的 design/cases/build 绑定成 context fingerprint；任一输入变化都使对应 review PASS 失效。

## 失败路由

- lint/check FAIL：先修第一处可行动问题，再重跑 lint/check；PASS 后继续下游。
- build FAIL：区分实现错误与环境/依赖错误；只修证据命中的范围。
- test FAIL：先确认是本次回归、既有失败还是环境问题，再决定修复。
- 任何修复改变源码后，旧 lint/check/build/test/review 证据全部失效；从最早失效的 required gate 重新运行，通常从 lint/check 开始。只有 source/context 未变化的环境重试可只跑失败 gate。
- 相同诊断连续两次没有进展时停止盲修，回 Plan 或询问用户；回 Plan 后恢复执行仍需用户明确执行授权。
- 同一 required gate 累计 FAIL 达 4 次（无论诊断是否更换）时必须询问用户，不得再走「回 Plan」分支。

独立 verifier 和 UI reviewer 只在 `plan-first-delivery` 的对应 gate 命中且客观验证 PASS 后启动。
