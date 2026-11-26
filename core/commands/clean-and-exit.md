---
description: Clean this task and pending cleanup, reclaim idle generated caches; --repo inventories only; --machine cleans machine caches
argument-hint: "[--repo [path] | --machine [--repo path]]"
---

Use `$HARNESS_ROOT/core/skills/cleanup-and-exit/SKILL.md` with these arguments:

$ARGUMENTS

No arguments cleans this task, reclaims its idle generated caches, and rechecks previously authorized pending cleanup in the same repositories. `--repo` is read-only; `--machine` authorizes rebuildable cache cleanup, not pending worktree removal or simulator data.
