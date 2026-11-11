# Active review contract

Resolve installed paths per the [host adapter](../rules/host-adapter.md) before running helpers.

Shared contract for `/review` backends. This command-level workflow is separate from `plan-first-delivery`'s conditional `verifier` role.

Order: report-only review first; cleanup runs only on a passing verdict; cleanup changes get one narrow recheck that re-anchors the published report to the final fingerprint.

## Inputs

- `base_ref`: freeze the explicit caller/project review base; otherwise resolve the remote default. If none is available, ask instead of guessing a branch.
- `review_fingerprint`: `"$HARNESS_ROOT/scripts/validation-receipt.sh" --repo "$repo" fingerprint`.
- `report_path`: `.reviews/<branch>-<timestamp>.md`.
- `cleanup_result`: structured result from the selected cleanup backend (see Cleanup JSON).
- `scratch`: per-run temporary directory, created once and removed on exit:

```bash
scratch="$(mktemp -d "${TMPDIR:-/tmp}/review-XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
main_result="$scratch/review-result.json"
temp_result="$scratch/final-result.json"
cleanup_json="$scratch/cleanup-result.json"
cleanup_diff="$scratch/cleanup.diff"
```

All transient run state — reviewer JSON, cleanup JSON, cleanup diff, tree ids, branch and timestamp scratch, stderr captures — lives only in `$scratch`. Never write it into the target repo or into the installed harness. The only artifacts that belong in the target repo are the `.reviews/` snapshot files plus the published report and its sidecar.

Freeze at start (the reviewer is read-only, so this snapshot is also the pre-cleanup snapshot):

```bash
snapshot_json="$(
  "$HARNESS_ROOT/scripts/review-input-snapshot.sh" \
    --repo "$repo" "$base_ref" "${branch_slug}-${timestamp}-pre-cleanup"
)"
snapshot_path="$(printf '%s' "$snapshot_json" | jq -r '.patch.path')"
untracked_manifest="$(printf '%s' "$snapshot_json" | jq -r '.untracked_manifest.path')"
```

Replace `/` in `branch_slug` with `-`. The helper writes the binary patch and JSON untracked manifest under `.reviews/` and returns their SHA-256 values.

Snapshot the tracked working tree in a temporary index to isolate cleanup. Check the frozen untracked manifest separately because cleanup may only edit tracked files.

```bash
tree_id() {
  local index="$scratch/tree-$1.idx"
  cp "$(git -C "$repo" rev-parse --path-format=absolute --git-path index)" "$index"
  GIT_INDEX_FILE="$index" git -C "$repo" add -u -- .
  GIT_INDEX_FILE="$index" git -C "$repo" write-tree
}
```

## Lifecycle

1. Freeze fingerprint, changed paths, relevant untracked paths, and snapshot. `pre_tree="$(tree_id pre)"`.
2. Start one read-only report-only reviewer over the frozen scope; capture its JSON in `$main_result`. Prefer one long wait. A running reviewer, progress output, or an empty temporary artifact is not failure.
3. Retry a terminal transport/TLS failure once with a fresh reviewer. For invalid JSON/schema, allow one repair-only follow-up with no tools or re-review.
4. Verdict `fail`: do not run cleanup. Write `cleanup_json` as `{"fixed":[],"skipped":[],"status":"not-run","reason":"review verdict fail"}` and publish `$main_result`.
5. Verdict `pass` / `pass-with-nits`: verify the original fingerprint still matches, then run cleanup over the same frozen scope. Verify cleanup left untracked product files intact. If the tree is unchanged (`tree_id post` equals `pre_tree`), publish `$main_result` with the cleanup JSON.
6. Cleanup changed the tree: start the required build verification, write `git -C "$repo" diff-tree -p --binary "$pre_tree" "$post_tree" >"$cleanup_diff"`, recompute the fingerprint, and run the cleanup recheck (below). Its output is `$temp_result`.
7. Recheck `must_fix` non-empty: verify the post-cleanup fingerprint still matches, check the reverse patch with `git -C "$repo" apply -R --check "$cleanup_diff"`, then reverse only that patch, confirm the fingerprint equals the frozen one, move every cleanup `fixed` entry to `skipped` with `reason` citing the recheck finding, set `status` to `reverted` with the same `reason`, and publish `$main_result`. The build result is reported but not acted on.
8. Otherwise publish `$temp_result` with the cleanup JSON. Join build verification and return `review-result.sh metadata` plus cleanup/build counts.

Before any publish, recompute the fingerprint and validate the chosen result against it.

Hard timeout: 30 minutes per reviewer run. Explicit user cancellation, a fingerprint change outside the backend's own cleanup, or timeout ends the review.

## Reviewer scope

Review `<base_ref>...HEAD` plus staged, unstaged, and initially frozen untracked product files. Exclude `.reviews/`, `.specs/`, build artifacts, and later-created files.

Reviewer may read changed files, direct callers/callees, applicable AGENTS/CLAUDE and trigger-on-touch docs, the latest plan/ExecPlan when supplied, and directly relevant manifests. It must not run build/lint/test/format/scanners, inspect caches or sibling repositories, use the network, edit, start agents, or post comments.

Only report issues introduced or exposed by the target diff. Every finding requires a repo-relative product path and line.

Tell the reviewer that cleanup (`reuse` / `simplification` / `efficiency` / `altitude`) runs after it on a passing verdict: it must not report those quality items as `suggestions`. `must_fix`, `test_residue`, `dead_code`, `plan_deviations`, and `perf_advisory` are unaffected.

Report a concrete package-boundary or ownership violation directly. Ordinary review does not load `architecture-first`; Root uses it later only when remediation has an unresolved material boundary choice.

Checklist:

1. correctness, error paths, concurrency, memory/thread safety, hot-path performance;
2. user plan and project-rule compliance;
3. package boundaries, ownership, resources, platform availability;
4. tests/debug residue and unused changed code;
5. iOS performance advisories.

## Cleanup recheck

One fresh read-only reviewer with the same prohibitions. Inputs: `$cleanup_diff`, `$main_result`, the cleanup JSON, the post-cleanup fingerprint, applicable rules, and the result schema. It inspects only the cleanup diff plus direct caller/callee context, judging behavior preservation (checklist 1) and rule compliance (checklist 2); it does not re-review the original target.

Output is the final JSON: `review_fingerprint` is the post-cleanup value; `must_fix` and other categories gain only findings introduced by the cleanup diff; every `$main_result` finding is carried over with `file` / `line` re-anchored to the current tree. A carried finding may be dropped only when the cleanup diff deleted the flagged code; name each drop in `assessment`. Summary and assessment otherwise come from `$main_result`.

## Model routing

- Codex: resolve the `branch-review` role through `scripts/model-policy.py`; do not duplicate model slugs in workflow prose.
- Raise to `xhigh` only for concurrency/ownership, auth/security/privacy, persistence/schema migration, cross-package public APIs, or at least 15 product files.
- Claude default: Opus high; use highest effort only for the same gates.
- Cleanup recheck: same role at `medium`; a run that hit a risk gate keeps the main review effort.

## Structured result

Return raw JSON matching `"$HARNESS_ROOT/core/skills/review-result.schema.json"`. No fence, preamble, report path, or duplicate counts.

Verdict is derived from findings:

- `fail`: `must_fix` non-empty;
- `pass-with-nits`: no `must_fix`, another category non-empty;
- `pass`: every category empty.

## Cleanup JSON

`fixed` and `skipped` arrays as the cleanup backend returns them, plus `status`: `run` (default when absent), `not-run`, or `reverted`. The latter two require a `reason` and an empty `fixed` array. Cleanup may edit only files tracked at snapshot time and must leave the Git index unchanged.

## Publish

Capture the result to publish (`$main_result` or `$temp_result` per Lifecycle) and run:

```bash
helper="$HARNESS_ROOT/scripts/review-result.sh"
"$helper" validate "$result" "$review_fingerprint"
"$helper" publish active "$result" "$review_fingerprint" \
  "$report_path" "$branch" "$base_ref" "$reviewer_label" \
  "$snapshot_path" "$cleanup_json"
"$helper" metadata "$result" "$report_path"
```

The backend, not the reviewer, owns report persistence. Only cleanup may edit product files, and only the backend's cleanup revert may undo them. Do not commit, push, create/merge a PR, post comments, run `/openpr`, or run `/pr-review`.
