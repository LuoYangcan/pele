# Architecture

Pele's center is a gated planner → generator → executor pipeline. The main agent coordinates roles and user decisions but does not write implementation code unless the user explicitly bypasses the pipeline.

## Control flow

```text
user request
  ↓
main agent: create worktree when required
  ↓
Lead Planner
  ├─ serial: publish canonical spec
  └─ fan-out: publish planning manifest
       ↓
     2–3 planner-workers write isolated drafts/reports
       ↓
     Spec Integrator publishes one canonical spec
  ↓
main agent: present spec and wait for explicit approval
  ↓
Generator: implement spec and run build verification
  ↓
Executor: read-only review, build/lint verification, PASS or FAIL
  ├─ PASS → report to user
  └─ FAIL → generator retry, at most three rounds
```

Fan-out is only a planning optimization. Workers never write the canonical spec; the Spec Integrator is its single initial writer. Small or coupled work stays serial.

## File contracts

```text
.specs/<slug>.md                         canonical index
.specs/<slug>/
  tasks/task-N.md                        implementation task details/status
  risks/risk-N.md                        risk details/status
  amendments/AMD-N.md                    approved changes after initial spec
  planning-manifest.yaml                 fan-out control plane, when used
  drafts/<shard-id>.md                   planner-worker proposal
  reports/<shard-id>.yaml                planner-worker persisted result
  questions/Q-*.yaml                     structured callback to the main agent
```

The canonical index plus child files are the implementation and review source of truth. Planning drafts and questions are control-plane artifacts; generator and executor consume only the integrated canonical spec.

## Enforcement

1. `PreToolUse` hooks block edits on protected branches and require `.specs/<slug>.md` or `.specs/<slug>.skip` in task worktrees.
2. `dispatch-pipeline` defines sequencing, user gates, retry routing, and role boundaries.
3. Agent definitions constrain read/write scope and structured results.

The main agent may create worktrees, relay decisions, inspect specs, and integrate approved results. It must not silently replace a planner, generator, executor, worker, or integrator.

## Installed layout

```text
~/.claude/
├── CLAUDE.md
├── rules/
├── agents/
├── commands/
├── skills/
├── templates/
├── scripts/
└── settings.json
```

Content entries are symlinked to `<pele-checkout>`; hooks are merged into `settings.json`. Pulling changes updates existing symlink targets immediately. Re-run `install.sh` when a release adds or removes top-level rules, agents, commands, skills, templates, scripts, or hook definitions.
