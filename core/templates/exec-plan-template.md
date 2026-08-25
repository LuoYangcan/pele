# <Title> ExecPlan

- **status**: active | blocked | superseded | complete
- **revision**: 1
- **owner**: Root
- **worktree**: <absolute path>
- **base ref**: <commit>

## Goal and done

<用户可观察结果与完成判据>

## Scope and constraints

- In scope: <...>
- Non-goals: <...>
- Hard constraints: <...>

## Decisions and affected surfaces

- <关键接口、数据流、兼容/迁移决策>
- Expected paths/modules: <...>

## Milestones and ownership

| Milestone | Owner | Dependencies | State |
| --- | --- | --- | --- |
| <result-oriented unit> | Root / worker-name | <none / milestone> | pending |

共享文件只由 Root 写；并行 writer 的文件 ownership 不得重叠。

## Verification and rollback

- Lint/check: `<command | not configured>`
- Build: `<command>`
- Targeted tests/behavior checks: `<command or steps | none + reason>`
- Independent/UI review gates: `<enabled + mandatory-risk/optional-requested + reason | disabled>`
- Just-in-time approval boundaries: `<exact destructive/irreversible/external actions | none>`
- Rollback/migration recovery: <...>

## Current handoff

- Confirmed facts: <...>
- Completed: <...>
- Next action: <...>
- Blockers: <none or concrete blocker>
