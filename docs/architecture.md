# Architecture

The center of pele is the **three-stage dispatch pipeline**. Everything else (rules, hooks, slash commands) is supporting infrastructure.

## Why three stages

A single agent doing the whole flow tends to:

- Plan and code in the same breath, producing specs that are really just implementation outlines
- Review its own code with implicit blind spots (it already convinced itself the implementation was right while writing it)
- Drift from the original requirement when implementation pushes back on the design

The three-stage split addresses these by giving each phase its own context, its own tool budget, and its own success criterion.

## The pipeline

```
                  ┌─────────────────────────────────────┐
                  │       User: "implement X"            │
                  └────────────────┬────────────────────┘
                                   ▼
                       ┌──────────────────────┐
                       │   main agent          │
                       │   (DISPATCHER ONLY)   │
                       └─────────┬────────────┘
                                 │ creates worktree if new topic
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
       ┌──────────┐       ┌──────────┐       ┌──────────┐
       │ planner  │       │generator │       │executor  │
       │          │       │          │       │          │
       │ writes   │       │ reads    │       │ reads    │
       │ .specs/  │       │ spec     │       │ spec +   │
       │ <slug>.md│       │ writes   │       │ code,    │
       │          │       │ code,    │       │ runs     │
       │ asks user│       │ runs     │       │ build +  │
       │ to clarify│      │ build    │       │ lint     │
       │          │       │          │       │          │
       │ NO code  │       │ NO PR    │       │ READ-ONLY│
       │          │       │ NO commit│       │ on repo  │
       └──────────┘       └──────────┘       └──────────┘
              │                  │                  │
              ▼                  ▼                  ▼
        spec ready         code + build OK    PASS  /  FAIL
              │                  │                  │
              ▼                  ▼          ┌───────┴───────┐
       user gates          executor          PASS           FAIL
       "go?"               runs              │              │
              │                              ▼              ▼
              ▼                       report user     loop back to
       generator                                       generator
                                                       (max 3x)
```

Subagents run via Claude Code's `Agent` tool. They share **no context** — only `.specs/<slug>.md` (a flat markdown file) and a small structured payload returned to the main agent.

## Why not let the main agent code

By design, the main agent never `Edit`s code or `.specs/` files. This is enforced by the `dispatch-pipeline` rule, not by tool permission — the main agent technically *could* call Edit but is instructed not to. The reason isn't safety; it's review hygiene:

> If the main agent wrote a line and then asked the executor to verify the work, the executor wouldn't know about that line — it only sees the generator's diff.

So: if the line wasn't generator-produced, executor can't review it. The main agent staying out of code keeps the audit trail clean.

The exception is **explicit user bypass**. If you say "just fix this typo, don't run the whole pipeline", the main agent does it directly.

## What enforces the contract

Three layers:

1. **Hooks** (hardest): `PreToolUse` on `Edit|Write|NotebookEdit` calls `check-spec.sh`. If you're inside `.worktrees/<slug>/` and `.specs/<slug>.md` doesn't exist, the edit is denied. Even the generator subagent can't bypass this — it would have to ask planner first.
2. **Rules** (medium): `dispatch-pipeline.md` is the contract the main agent follows. It's the file the main agent reads when it sees a code-writing request.
3. **Subagent prompts** (softest): Each subagent's `.md` file in `agents/` defines what it does and (more importantly) what it doesn't. The forbidden lists at the bottom of each are what keeps roles from creeping.

## Spec is the source of truth

The `.specs/<slug>.md` file produced by planner is the **only** thing all three subagents share:

```
       planner WRITES sections 1-7
                  │
                  ▼
            spec on disk
                  │
       ┌──────────┴──────────┐
       ▼                     ▼
   generator             executor
   READS all              READS all
   WRITES section 8       WRITES nothing
   (progress only)
```

If generator hits something the spec doesn't cover, it stops, asks the user, and tells the main agent to call planner again with the new info. Planner updates the spec; only then does generator continue. This way executor never sees half-decided design.

## Failure handling

```
executor: FAIL → main agent: send issues to generator → generator: retry
                          ↑                                    │
                          └────────────────────────────────────┘
                                      max 3 times
                                          │
                                          ▼
                              after 3 failures: main agent
                              reports to user, who decides:
                              - revise spec (call planner)
                              - take over and edit directly
                              - abandon and pause the worktree
```

Three retries is a hard cap — you don't want generator and executor in an infinite "fix the same thing different way" loop. After the cap, the issue is no longer in the code; it's in the spec or in the human's understanding of what's needed.

## Where things live after install

```
~/.claude/
├── CLAUDE.md          → <pele-checkout>/core/CLAUDE.md
├── rules/<name>.md    → <pele-checkout>/core/rules/<name>.md
├── agents/<name>.md   → <pele-checkout>/core/agents/<name>.md
├── commands/<name>.md → <pele-checkout>/core/commands/<name>.md
├── skills/<name>      → <pele-checkout>/core/skills/<name>      (symlink dir)
├── templates/<name>.md→ <pele-checkout>/core/templates/<name>.md
├── scripts/<name>.sh  → <pele-checkout>/scripts/<name>.sh
└── settings.json      (regular file — only the .hooks key is managed by pele)
```

`<pele-checkout>` is wherever you cloned pele (defaults to `~/Developer/pele/` via `bootstrap.sh`, override with `PELE_INSTALL_DIR=`; or clone manually anywhere and run `./install.sh` from there — it auto-detects its location).

Symlinks mean `git pull` in the pele repo updates everything in `~/.claude/` instantly. No reinstall needed for content updates. The exception is `settings.json` (because it's a JSON merge, not a symlink) — re-run `install.sh` if you change `core/hooks/settings.hooks.json`.
