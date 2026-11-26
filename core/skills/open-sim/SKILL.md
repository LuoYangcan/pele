---
name: open-sim
description: Build the iOS app with a script, install and launch it on the Simulator leased to the current checkout, then bring the Simulator window to the front. Use when the user asks to open the simulator, build and run, or see a change in the simulator; use run-device for a real iPhone. Not for macOS or release/archive builds.
---

# Open Simulator

Run the shared `$HARNESS_ROOT/scripts/run-ios.sh` instead of chaining build/install/launch commands by hand. `run-device` uses the same script.

```bash
bash "$HARNESS_ROOT/scripts/run-ios.sh" --target sim
```

- Run it anywhere inside the iOS checkout. It builds with `RUN_IOS_BUILD_CMD`, the project's simulator build command (default `just build-ios`; an `xcodebuild ... build` line also works), and reads products from `RUN_IOS_DERIVED` (default `build/DerivedData`). `--derived <path>` overrides the DerivedData path for one run.
- Add `--no-build` only when the user explicitly asks to reuse the existing artifact.
- `$HARNESS_ROOT/scripts/worktree-sim.sh ensure` leases the most recently used free existing iPhone (iPad and legacy `sim-<slug>` devices excluded), keeping its login state. The same checkout keeps its device; another checkout can take it only after cleanup, checkout removal or 2 idle hours. It never creates a simulator; when ensure fails, stop instead of switching to another simulator. The script waits for boot before installing.
- On success, relay `WHERE`, `UDID`, `BUNDLE_ID` and `PID` from the `----- run-ios result -----` block. On failure, report the `ERROR:` output; a successful build is not a successful install and launch.

Exit codes: 1 precondition or selection failure, 2 build failure, 3 artifact or bundle ID not found, 4 simulator, install or launch failure. Do not switch devices, skip the build, retry or widen cache cleanup on your own. Route SPM resolve or binary-artifact failures to the project's package bootstrap step.
