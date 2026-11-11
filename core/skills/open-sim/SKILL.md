---
name: open-sim
description: Build the iOS app, then install + launch it on the simulator leased to this checkout and bring the window to front. Use when the user asks to "open the simulator", "open simulator", "run the simulator", "see how it looks in the simulator", "build and run it", "build and run on simulator", "launch on simulator". Skip for macOS app; for a real iPhone use the `run-device` skill instead.
---

# open-sim

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

"Build → install → launch → bring the Simulator window to the front" in one shot. The mechanical part lives in the shared script `"$HARNESS_ROOT/scripts/run-ios.sh"` (`--target sim`); this skill only calls it and relays the result to the user. The real-device counterpart is `run-device` (`--target device`), sharing the same script.

## When to use

- Just changed iOS code and want to build + see it in the simulator right away
- Want to build + launch the app from the command line without opening Xcode

Not for: macOS apps · **a real device (use `run-device`)** · release / archive artifacts.

## Assumptions

- cwd is somewhere inside the iOS repo (worktree included), with a `justfile` findable upward
- The project builds iOS Simulator Debug with `just build-ios`
- An existing iPhone simulator must be available to lease. The checkout reuses its lease while active, and cleanup releases it without losing app data or login state.

## Run

Build every time by default (so you see the current code):

```bash
bash "$HARNESS_ROOT/scripts/run-ios.sh" --target sim
```

- The user **explicitly** says "no build / skip compiling / just install the existing artifact" → add `--no-build`:
  ```bash
  bash "$HARNESS_ROOT/scripts/run-ios.sh" --target sim --no-build
  ```

The script builds → locates the build artifact (scans `Build/Products/*-iphonesimulator/`, takes the newest `.app`; the configuration name is project-defined and can change, so `Debug-` is not hardcoded) → reads the bundle id from the artifact's `Info.plist` → leases the most recently used free iPhone simulator and waits for boot → `simctl install` + `launch` → `open-simulator.sh` (Simulator.app, or DeviceHub.app on Xcode 27), and finally prints the `----- run-ios result -----` result block.

## Report to the user

Relay from the result block: which sim was used (`WHERE`) + UDID + `BUNDLE_ID` + `PID`. On any step failure the script emits `ERROR:` and exits non-zero — **report the error to the user verbatim, do not automatically try another approach**.

## Save context (optional)

`just build-ios` spits out thousands of lines of xcodebuild log. To keep it out of the main conversation: on Claude dispatch Haiku / Sonnet; on Codex dispatch `command-runner` (Luna low), or Terra low when that role is not loaded. The subagent only runs the command and returns the result block; it does not judge code quality.

## Failure handling (script exit codes)

| Exit code | Meaning | What to do |
|---|---|---|
| 2 | Build failed | Report the xcodebuild error verbatim, do not continue |
| 3 | No `.app` found | Only possible with `--no-build`; have the user drop `--no-build` and re-run |
| 4 | install / launch / Simulator window failed, or no usable iPhone sim | Check the reported lease, boot, install or launch error |

## Out of scope

- ❌ Does not run `just generate` · does not switch scheme · does not handle macOS / a real device (real device goes to `run-device`)
- ❌ Does not skip the build unless the user explicitly asks (builds every time by default)
