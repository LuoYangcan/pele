---
name: scan-trigger-docs
description: Scan project AGENTS.md and CLAUDE.md for trigger-on-touch documentation markers, then Read every referenced doc whose scope intersects the current task. Use before planning, implementation, or review. Skip for meta-only work or when neither project instruction file exists.
---

# scan-trigger-docs

Read project instruction files and follow every documentation trigger that may intersect the current scope.

## Trigger

- Planner: before freezing hard constraints, risks, or acceptance cases.
- Generator: after choosing the current task and before editing code.
- Executor: before judging the changed files.
- Any agent that needs project-specific invariants not present in its current context.

Skip when the task only changes agent/tool configuration or documentation, or the project has neither `AGENTS.md` nor `CLAUDE.md`.

## Procedure

### 1. Find the project root

Walk upward from `cwd` to the nearest ancestor containing either instruction file:

```bash
ROOT="$PWD"
while [[ "$ROOT" != "/" && ! -f "$ROOT/AGENTS.md" && ! -f "$ROOT/CLAUDE.md" ]]; do
  ROOT="$(dirname "$ROOT")"
done
[[ -f "$ROOT/AGENTS.md" || -f "$ROOT/CLAUDE.md" ]] || exit 0
```

Use the files inside the active worktree, not another checkout.

### 2. Read instruction files in full

Read every existing file:

- `$ROOT/AGENTS.md`
- `$ROOT/CLAUDE.md`

Follow any delegated trigger index they name, such as `docs/SUBSYSTEMS.md`. Do not assume a Markdown link was injected into context.

### 3. Build the trigger table

For each “read this doc before changing …” marker, record:

- referenced doc path;
- listed paths, modules, types, or concepts;
- source instruction file and section.

Accept project-specific marker wording; do not require one exact heading.

### 4. Match the current scope

Read a referenced doc when any condition holds:

- a planned or changed file is inside its listed path;
- the task names a listed type, function, module, or behavior;
- the task is semantically related to the doc topic;
- the boundary is uncertain.

Skip only when the current scope is provably unrelated.

### 5. Read matched docs in full

Read each matched document, then repeat the same check for nested trigger references. Do not use grep/head excerpts as a substitute for the full document.

Optionally inspect project-specific IDE rule files when their names indicate a direct match:

```bash
ls "$ROOT/.cursor/rules/" 2>/dev/null
```

### 6. Apply the constraints

- Planner: write matched invariants into spec constraints/risks and cite the doc.
- Generator: implement against those invariants; route uncovered ambiguity through the feedback flow.
- Executor: verify the diff against them and cite violations.

## Output

This skill does not require a standalone result. A caller may include:

```yaml
trigger_docs_read:
  - docs/example.md
```

## Prohibited

- Do not edit project trigger markers.
- Do not reuse a previous agent's scan without rereading current worktree files.
- Do not scan unrelated global docs or changelogs.

<!-- Why core: independent agent contexts must rediscover the same project-specific invariants before acting. -->
