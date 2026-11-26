---
name: find-ios-build-artifact
description: On explicit request, read the `.app`, bundle ID and leased Simulator UDID of a just-finished iOS Simulator build. Skip when the caller already has a bound artifact.
---

# find-ios-build-artifact

Use only when a caller explicitly asks for it. It locates an existing iOS Simulator product; it does not build, install or launch.

## Prefer the run-ios result

`open-sim` (`run-ios.sh --target sim`) prints a `----- run-ios result -----` block for the run. When the caller has that block, read `TARGET`, `APP_PATH`, `BUNDLE_ID` and `UDID` from it; require `TARGET=sim` and check that `$APP_PATH/Info.plist` exists. Do not search for or guess a "latest" artifact.

That `UDID` is already this checkout's leased simulator; do not call `worktree-sim.sh ensure` again.

## Standalone workspace path

Without that result, the caller must supply the workspace, scheme and the configuration the build actually used, plus the DerivedData path if the build set one. Run:

```bash
xcrun xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings
```

Add `-derivedDataPath "$DERIVED_DATA"` when the build used a custom DerivedData. Parse `BUILT_PRODUCTS_DIR`, `FULL_PRODUCT_NAME` and `PRODUCT_BUNDLE_IDENTIFIER` into `APP_PATH` and `BUNDLE_ID`, and confirm `$APP_PATH/Info.plist` exists. When there is no `.app`, return `BUILD_ARTIFACT_NOT_FOUND` without building; never guess the scheme, configuration, DerivedData or product.

When a simulator is needed, lease one for the current checkout:

```bash
bash "$HARNESS_ROOT/scripts/worktree-sim.sh" ensure
```

Accept only the `SIMULATOR_UDID` it prints; on failure report the lease failure instead of picking another device.

## Output and boundaries

Output `APP_PATH`, `BUNDLE_ID`, `SIMULATOR_UDID`, plus the workspace/scheme when known. Skip or hand back to the caller when:

- The caller already has an app, bundle and simulator bound to the build identity; UI review in particular must not switch to the "most recent" artifact.
- The target is macOS, a real device, a bare `.xcodeproj` or an SPM-only project.
- The artifact is missing, the scheme/workspace is ambiguous, or no simulator can be leased.

Do not build, install, launch or let the caller replace the leased UDID.
