#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  review-result.sh validate <result.json> <expected-fingerprint>
  review-result.sh publish active <result.json> <expected-fingerprint> <report.md> <branch> <base-ref> <reviewer-label> <snapshot-path> <cleanup.json>
  review-result.sh metadata <result.json> <report.md>

The reviewer result is the structured source of truth. publish validates it,
stores a JSON sidecar next to the report, and renders canonical Markdown.
EOF
}

die() {
  printf 'review-result: %s\n' "$*" >&2
  exit 2
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

validate_result() {
  local result="$1"
  local expected_fingerprint="$2"
  [[ -f "$result" ]] || die "result file not found: $result"

  jq -e --arg expected_fingerprint "$expected_fingerprint" '
    def other_count:
      ([
        (.findings.suggestions | length),
        (.findings.test_residue | length),
        (.findings.dead_code | length),
        (.findings.plan_deviations | length),
        (.findings.perf_advisory | length)
      ] | add);
    def expected_verdict:
      if (.findings.must_fix | length) > 0 then "fail"
      elif other_count > 0 then "pass-with-nits"
      else "pass"
      end;
    .schema_version == 1
    and .review_fingerprint == $expected_fingerprint
    and (.review_fingerprint | type == "string" and length > 0)
    and (.verdict == "pass" or .verdict == "pass-with-nits" or .verdict == "fail")
    and (.summary | type == "string" and length > 0 and (contains("\n") | not))
    and (.assessment | type == "string" and length > 0)
    and (.findings | type == "object")
    and ((.findings | keys | sort) == [
      "dead_code",
      "must_fix",
      "perf_advisory",
      "plan_deviations",
      "suggestions",
      "test_residue"
    ])
    and ([.findings[] | type] | all(. == "array"))
    and ([.findings[] | .[]] | all(.[];
      type == "object"
      and (.file | type == "string"
        and length > 0
        and (startswith("/") | not)
        and (test("(^|/)\\.\\.(/|$)") | not)
        and (startswith(".reviews/") | not)
        and (startswith(".specs/") | not)
        and (contains("\n") | not)
        and (contains("\t") | not))
      and (.line | type == "number" and . >= 1 and floor == .)
      and (.summary | type == "string" and length > 0 and (contains("\n") | not) and (contains("\t") | not))
    ))
    and .verdict == expected_verdict
  ' "$result" >/dev/null || die "invalid reviewer result or fingerprint/verdict mismatch"
}

validate_cleanup() {
  local cleanup="$1"
  [[ -f "$cleanup" ]] || die "cleanup file not found: $cleanup"
  jq -e '
    (.fixed | type == "array")
    and (.skipped | type == "array")
    and (.fixed | all(.[];
      (.file | type == "string"
        and length > 0
        and (startswith("/") | not)
        and (test("(^|/)\\.\\.(/|$)") | not)
        and (startswith(".reviews/") | not)
        and (startswith(".specs/") | not)
        and (contains("\n") | not)
        and (contains("\t") | not))
      and (.line | type == "number" and . >= 1 and floor == .)
      and (.category == "reuse" or .category == "simplification" or .category == "efficiency" or .category == "altitude")
      and (.summary | type == "string" and length > 0 and (contains("\n") | not) and (contains("\t") | not))
    ))
    and (.skipped | all(.[];
      (.file | type == "string"
        and length > 0
        and (startswith("/") | not)
        and (test("(^|/)\\.\\.(/|$)") | not)
        and (startswith(".reviews/") | not)
        and (startswith(".specs/") | not)
        and (contains("\n") | not)
        and (contains("\t") | not))
      and (.line | type == "number" and . >= 1 and floor == .)
      and (.category == "reuse" or .category == "simplification" or .category == "efficiency" or .category == "altitude")
      and (.summary | type == "string" and length > 0 and (contains("\n") | not) and (contains("\t") | not))
      and (.reason | type == "string" and length > 0 and (contains("\n") | not) and (contains("\t") | not))
    ))
  ' "$cleanup" >/dev/null || die "invalid cleanup result"
}

append_findings() {
  local result="$1"
  local category="$2"
  local empty_text="$3"
  local row evidence summary

  if [[ "$(jq --arg category "$category" '.findings[$category] | length' "$result")" -eq 0 ]]; then
    printf '%s\n' "$empty_text"
    return
  fi

  while IFS=$'\t' read -r evidence summary; do
    printf -- '- [ ] **%s** — %s\n' "$evidence" "$summary"
  done < <(jq -r --arg category "$category" \
    '.findings[$category][] | ["\(.file):\(.line)", .summary] | @tsv' "$result")
}

append_cleanup_fixed() {
  local cleanup="$1"
  local evidence summary category

  if [[ "$(jq '.fixed | length' "$cleanup")" -eq 0 ]]; then
    printf '无可修项。\n'
    return
  fi

  while IFS=$'\t' read -r evidence summary category; do
    printf -- '- **%s** — %s（%s）\n' "$evidence" "$summary" "$category"
  done < <(jq -r '.fixed[] | ["\(.file):\(.line)", .summary, .category] | @tsv' "$cleanup")
}

append_cleanup_skipped() {
  local cleanup="$1"
  local evidence summary reason

  if [[ "$(jq '.skipped | length' "$cleanup")" -eq 0 ]]; then
    printf '无。\n'
    return
  fi

  while IFS=$'\t' read -r evidence summary reason; do
    printf -- '- [ ] **%s** — %s · 跳过原因：%s\n' "$evidence" "$summary" "$reason"
  done < <(jq -r '.skipped[] | ["\(.file):\(.line)", .summary, .reason] | @tsv' "$cleanup")
}

render_report() {
  local mode="$1"
  local result="$2"
  local output="$3"
  local branch="$4"
  local base_ref="$5"
  local reviewer_label="$6"
  local snapshot_path="${7:-}"
  local cleanup="${8:-}"
  local fingerprint verdict summary assessment now

  fingerprint="$(jq -r '.review_fingerprint' "$result")"
  verdict="$(jq -r '.verdict' "$result")"
  summary="$(jq -r '.summary' "$result")"
  assessment="$(jq -r '.assessment' "$result")"
  now="$(date '+%Y-%m-%d %H:%M')"

  {
    printf '<!-- review-fingerprint: %s -->\n' "$fingerprint"
    printf '# Code Review: %s\n\n' "$branch"
    printf '> 时间：%s · 范围：%s...HEAD + 未提交改动（含 cleanup 落地的清理）\n' "$now" "$base_ref"
    printf '> Reviewer: %s（report-only）\n' "$reviewer_label"
    printf '> 清理前快照：%s\n\n' "$snapshot_path"
    printf '## Verdict\n\n`%s`\n\n一句话总结：%s\n\n' "$verdict" "$summary"
    printf '## 必修（fail-blocking）\n\n'
    append_findings "$result" must_fix '无。'
    printf '\n## 建议（nice-to-have）\n\n'
    append_findings "$result" suggestions '无。'
    printf '\n## Cleanup 已落地的质量修复\n\n'
    append_cleanup_fixed "$cleanup"
    printf '\n## Cleanup 跳过的发现\n\n'
    append_cleanup_skipped "$cleanup"
    printf '\n## 测试用代码残留\n\n'
    append_findings "$result" test_residue '无残留。'
    printf '\n## 无用代码残留\n\n'
    append_findings "$result" dead_code '无残留。'
    printf '\n## iOS 性能反模式（建议层，非阻断）\n\n'
    append_findings "$result" perf_advisory '无。'
    printf '\n## 最终计划 / 项目规范偏离\n\n'
    append_findings "$result" plan_deviations '全部符合。'
    printf '\n## 整体评估\n\n%s\n' "$assessment"
  } >"$output"
}

publish_result() {
  local mode="$1"
  local result="$2"
  local expected_fingerprint="$3"
  local report="$4"
  local branch="$5"
  local base_ref="$6"
  local reviewer_label="$7"
  local snapshot_path="${8:-}"
  local cleanup="${9:-}"
  local report_dir result_sidecar report_temp result_temp

  [[ "$mode" == "active" ]] || die "invalid mode: $mode"
  [[ "$report" == *.md ]] || die "report path must end in .md"
  [[ "$report" == .reviews/*.md || "$report" == */.reviews/*.md ]] || die "report path must be inside .reviews"
  [[ "$report" != *"/../"* && "$report" != ../* ]] || die "report path must not traverse parent directories"
  [[ "$branch" != *$'\n'* && "$base_ref" != *$'\n'* && "$reviewer_label" != *$'\n'* ]] || die "report metadata must be single-line"
  validate_result "$result" "$expected_fingerprint"
  [[ -n "$snapshot_path" && -n "$cleanup" ]] || die "active mode requires snapshot and cleanup result"
  [[ -f "$snapshot_path" ]] || die "snapshot file not found: $snapshot_path"
  validate_cleanup "$cleanup"

  report_dir="$(dirname "$report")"
  result_sidecar="${report%.md}.json"
  mkdir -p "$report_dir"
  report_temp="$(mktemp "$report_dir/.review-report.XXXXXX")"
  result_temp="$(mktemp "$report_dir/.review-result.XXXXXX")"
  trap 'rm -f "$report_temp" "$result_temp"' RETURN

  render_report "$mode" "$result" "$report_temp" "$branch" "$base_ref" "$reviewer_label" "$snapshot_path" "$cleanup"
  jq '.' "$result" >"$result_temp"
  mv "$result_temp" "$result_sidecar"
  mv "$report_temp" "$report"
  trap - RETURN
  printf '%s\n' "$report"
}

metadata() {
  local result="$1"
  local report="$2"
  jq --arg report "$report" --arg result_file "${report%.md}.json" '{
    review_status: "success",
    review_verdict: .verdict,
    review_findings_count: {
      must_fix: (.findings.must_fix | length),
      suggestions: (.findings.suggestions | length),
      test_residue: (.findings.test_residue | length),
      dead_code: (.findings.dead_code | length),
      plan_deviations: (.findings.plan_deviations | length),
      perf_advisory: (.findings.perf_advisory | length)
    },
    review_summary: .summary,
    review_file: $report,
    review_result_file: $result_file
  }' "$result"
}

main() {
  require_jq
  local command="${1:-}"
  case "$command" in
    validate)
      [[ "$#" -eq 3 ]] || { usage >&2; exit 2; }
      validate_result "$2" "$3"
      ;;
    publish)
      [[ "${2:-}" == "active" && "$#" -eq 10 ]] || { usage >&2; exit 2; }
      publish_result "${@:2}"
      ;;
    metadata)
      [[ "$#" -eq 3 ]] || { usage >&2; exit 2; }
      metadata "$2" "$3"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
