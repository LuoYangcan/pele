---
name: review-mobile-ui
description: iOS Simulator UI acceptance SOP. Run by ui-reviewer when Figma, animation, complex UI or an explicit user request is involved, checking an existing runnable build with static screenshots and dynamic screen recordings. Does not build or modify source.
---

# Mobile UI review

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

The caller must supply the explicit cases from the final plan, build evidence for the current source, the frozen design artifacts, a `build=` bound to the actual `.app`/environment, and a `ui_review_input_fingerprint` matching those inputs. Answer only those cases, no exploratory testing; return `NEEDS_INPUT` when the fingerprint does not match.

## Supported scope

- iOS Simulator: supported.
- Android, real devices, macOS, watchOS, tvOS: not covered by this skill, return `DEGRADED target_not_supported`.
- Missing explicit UI cases or design basis: return `NEEDS_INPUT`.
- Missing an absolute `APP_PATH`, app digest, bundle/scheme/config/destination or the designated Simulator: return `NEEDS_INPUT build_identity_incomplete`; do not build on your own or search for another artifact.

## 1. Locate the artifact and Simulator

Use only the `APP_PATH`, `BUNDLE_ID`, scheme/config/destination and `SIMULATOR_UDID` bound by the caller. First check the digest with `validation-receipt.sh --repo "$repo" artifact-digest "$APP_PATH"` and the bundle ID with `plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist"`; on a mismatch return `NEEDS_INPUT build_identity_mismatch`. Do not load `find-ios-build-artifact` or switch to the "most recent" artifact.

If the designated artifact or Simulator does not exist, degrade as an environment limitation. Every subsequent `sim-use` command must pass `--device "$SIMULATOR_UDID"` explicitly.

## 2. Install and launch

Execute once for the whole review session:

```bash
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
bash "$HARNESS_ROOT/scripts/open-simulator.sh" "$SIMULATOR_UDID"
```

On failure return `DEGRADED install_or_launch_failed`. Do not reinstall, relaunch or switch to another Simulator hoping for luck.

## 3. Evidence directory

```bash
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="$repo/.reviews/ui-${WORKTREE_SLUG}-${timestamp}"
mkdir -p "$evidence_dir/refs"
```

## 4. Case classification

| Category | Signal | Path |
| --- | --- | --- |
| Static | frame, spacing, alignment, layout, font size, color, corner radius, static state | one AX tree + one screenshot |
| Dynamic | animation, transition, expand/collapse, input change, loading, gesture, keyboard, toast, sheet | `record-ui-animation` |
| Unclear | the case description is not enough to judge | dynamic path; if still unjudgeable, `NEEDS_INPUT` |

Navigate to the target state by the shortest path the case gives. Operate only the app under test; do not change other apps or system settings.

## 5. Static cases

Budget per case: the necessary navigation, one wait for stability, one core `sim-use ui`, one `sim-use screenshot`. Read the AX tree one extra time only when no stable accessibility selector can be found; do not sample repeatedly.

```bash
sim-use ui --device "$SIMULATOR_UDID"
sim-use screenshot --device "$SIMULATOR_UDID" \
  --output "$evidence_dir/case-<id>-static.png"
```

- Compute size/spacing from AX frames, default tolerance ±2pt; when the final plan sets another tolerance, follow the plan.
- When a frozen measurement HTML exists, it is the source for exact numbers.
- Prefer the frozen reference already bound in `design=`; fetch a reference screenshot into `refs/` once only when the input carries an immutable provider version and the live result can be checked against that version.
- `strict`: any visual deviation within the plan's coverage may be blocking; `loose`: block only on the layout skeleton or obviously wrong tokens, record details as warnings.
- A single Figma fetch failure is recorded as an environment warning; when every reference fails and judgment is impossible, `DEGRADED figma_reference_unavailable`.

During static sampling do not use type, paste, swipe, long-press or repeated taps to produce dynamic states.

## 6. Dynamic cases

Load `record-ui-animation` once per dynamic case and follow its prepare → record → trigger → stop → extract flow. Commands such as type/paste/swipe/gesture may trigger the planned interaction only inside the recording window; trigger once per case.

Read every keyframe and check the start, middle and end states, timing, misalignment, flicker and the plan's requirements. Do not substitute a single-frame screenshot for judging an animation.

Skip the case and record an environment limitation instead of blindly re-recording when: the record/extract script fails, there are fewer than 2 frames, the trigger primitive is unreliable, or the keyframes are not enough to judge. If the remaining evidence still suffices, the whole can PASS with a manual smoke test requested; if no dynamic case can be judged, `DEGRADED`.

## 7. Summary

- `PASS`: every judgeable case passes; isolated non-critical environment gaps may be listed for a manual smoke test.
- `FAIL`: any explicit case shows a reproducible visual, animation, interaction or crash deviation.
- `DEGRADED`: the environment makes a key case unjudgeable, and this cannot be attributed to the implementation.
- `NEEDS_INPUT`: the cases, expectations or design basis are themselves insufficient.

Return a verdict, an absolute evidence path and a one-line observation per case; a FAIL issue must point at a screenshot or a frames directory. Do not lower the bar because of the number of retries.

Before summarizing, re-check the app digest and the UI context fingerprint, and record the evidence digest with `validation-receipt.sh --repo "$repo" artifact-digest "$evidence_dir"`. Report the actual Simulator/runtime, locale, appearance and Dynamic Type; discard the results if any bound input changed inside the window.
