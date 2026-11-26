---
name: run-device
description: Build, install and launch the iOS app on a connected real iPhone with a script. Use when the user asks to install on a device, take a quick look on the iPhone, or deploy to their phone; use open-sim for the simulator. Not for macOS or release/archive builds.
---

# Run on iPhone

Run the shared `$HARNESS_ROOT/scripts/run-ios.sh` instead of chaining build/install/launch commands by hand. `open-sim` uses the same script.

```bash
bash "$HARNESS_ROOT/scripts/run-ios.sh" --target device
```

- Run it anywhere inside the iOS checkout. The iPhone must be connected, unlocked and trusting this computer. Signing comes from the project's configuration (e.g. a local `.xcconfig`); the script never changes signing or provisioning.
- It builds with `RUN_IOS_BUILD_CMD` (default `just build-ios`) and passes the destination through the env var named by `RUN_IOS_DEST_ENV`, which the device target requires (e.g. `RUN_IOS_DEST_ENV=IOS_DEST` for a justfile that reads `IOS_DEST`). Products come from `RUN_IOS_DERIVED` (default `build/DerivedData`) or `--derived <path>`.
- With exactly one paired device it picks that one, warning when its tunnel is not `connected`; with several it lists them and stops. Pass `--device-id <CoreDevice identifier>` to choose explicitly.
- Add `--no-build` only when the user explicitly asks to reuse the existing artifact.
- On success, relay `WHERE`, `UDID` (the CoreDevice identifier), `BUNDLE_ID` and `PID` from the `----- run-ios result -----` block. On any failure, report the `ERROR:` output and do not try another device.

Exit codes: 1 precondition or device selection failure, 2 build failure, 3 artifact or bundle ID not found, 4 install or launch failure. Do not change signing, skip the build, retry or clean caches on your own. Route SPM resolve or binary-artifact failures to the project's package bootstrap step.
