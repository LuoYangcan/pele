# Active review contract

Shared contract for `/review` backends. This command-level workflow is separate from `plan-first-delivery`'s conditional `verifier` role.

## Inputs

- `base_ref`: repository review base, normally `dev`.
- `review_fingerprint`: `"$HOME/.claude/scripts/validation-receipt.sh" --repo "$repo" fingerprint`.
- `report_path`: `.reviews/<branch>-<timestamp>.md`.
- `cleanup_result`: structured result from the selected cleanup backend.
- `scratch`: per-run temporary directory, created once and removed on exit:

```bash
scratch="$(mktemp -d "${TMPDIR:-/tmp}/review-XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
temp_result="$scratch/review-result.json"
cleanup_json="$scratch/cleanup-result.json"
```

All transient run state — reviewer JSON, cleanup JSON, branch and timestamp scratch, stderr captures — lives only in `$scratch`. Never write it into the target repo or into `~/.claude`. The only artifacts that belong in the target repo are the `.reviews/` snapshot files plus the published report and its sidecar.

Freeze before cleanup:

```bash
snapshot_json="$(
  "$HOME/.claude/scripts/review-input-snapshot.sh" \
    --repo "$repo" "$base_ref" "${branch_slug}-${timestamp}-pre-cleanup"
)"
snapshot_path="$(printf '%s' "$snapshot_json" | jq -r '.patch.path')"
untracked_manifest="$(printf '%s' "$snapshot_json" | jq -r '.untracked_manifest.path')"
```

Replace `/` in `branch_slug` with `-`. The helper writes the binary patch and JSON untracked manifest under `.reviews/` and returns their SHA-256 values.

## Lifecycle

1. Freeze fingerprint, changed paths, relevant untracked paths, and snapshot.
2. Run cleanup. If cleanup changes code, start the required build verification.
3. Recompute the fingerprint, then start one read-only report-only reviewer over the frozen scope.
4. Prefer one long wait. A running reviewer, progress output, or an empty temporary artifact is not failure.
5. Retry a terminal transport/TLS failure once with a fresh reviewer. For invalid JSON/schema, allow one repair-only follow-up with no tools or re-review.
6. Recompute fingerprint before publish; reject stale output. Validate and publish through `scripts/review-result.sh`.

Hard timeout: 30 minutes. Explicit user cancellation, fingerprint change, or timeout ends the review.

## Reviewer scope

Review `<base_ref>...HEAD` plus staged, unstaged, and initially frozen untracked product files. Exclude `.reviews/`, `.specs/`, build artifacts, and later-created files.

Reviewer may read changed files, direct callers/callees, applicable AGENTS/CLAUDE and trigger-on-touch docs, the latest plan/ExecPlan when supplied, and directly relevant manifests. It must not run build/lint/test/format/scanners, inspect caches or sibling repositories, use the network, edit, start agents, or post comments.

Only report issues introduced or exposed by the target diff. Every finding requires a repo-relative product path and line.

Report a concrete package-boundary or ownership violation directly. Ordinary review does not load `architecture-first`; Root uses it later only when remediation has an unresolved material boundary choice.

Checklist:

1. correctness, error paths, concurrency, memory/thread safety, hot-path performance;
2. user plan and project-rule compliance;
3. package boundaries, ownership, resources, platform availability;
4. tests/debug residue and unused changed code;
5. iOS performance advisories.

## Model routing

- Codex default: `gpt-5.6-sol`, reasoning `high`.
- Raise to `xhigh` only for concurrency/ownership, auth/security/privacy, persistence/schema migration, cross-package public APIs, or at least 15 product files.
- Claude default: Opus high; use highest effort only for the same gates.

## Structured result

Return raw JSON matching `~/.claude/skills/review-result.schema.json`. No fence, preamble, report path, or duplicate counts.

Verdict is derived from findings:

- `fail`: `must_fix` non-empty;
- `pass-with-nits`: no `must_fix`, another category non-empty;
- `pass`: every category empty.

## Publish

Capture the reviewer JSON in `$temp_result` (see Inputs), then run:

```bash
helper="$HOME/.claude/scripts/review-result.sh"
"$helper" validate "$temp_result" "$review_fingerprint"
"$helper" publish active "$temp_result" "$review_fingerprint" \
  "$report_path" "$branch" "$base_ref" "$reviewer_label" \
  "$snapshot_path" "$cleanup_json"
"$helper" metadata "$temp_result" "$report_path"
```

The backend, not the reviewer, owns report persistence. Only cleanup may edit product files. Do not commit, push, create/merge a PR, post comments, run `/openpr`, or run `/pr-review`.

Cleanup JSON contains `fixed` and `skipped` arrays. Cleanup may edit only files tracked at snapshot time; it must not edit existing untracked files or create product files.
