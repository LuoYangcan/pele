---
name: find-ios-build-artifact
description: Locate a just-built iOS Simulator `.app` and the leased Simulator UDID. Output `APP_PATH`, `BUNDLE_ID`, and `SIMULATOR_UDID` for UI review/open-sim callers. Skip when all values are already known, no `.xcworkspace` ancestor exists, the app has not been built, or the target is macOS/device.
---

# find-ios-build-artifact

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

After an iOS Simulator build finishes, find the build artifact `.app` path, bundle ID, and the simulator UDID leased to the current checkout. Pass these values to `simctl install <udid> <app>` and `simctl launch <udid> <bundle>`.

Lease an existing iPhone with `"$HARNESS_ROOT/scripts/worktree-sim.sh" ensure`. A live lease prevents other checkouts from selecting the same device.

## Triggers

The caller's SOP needs all three of `APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID`, and an iOS Simulator build has already run. Common cases:

- **ui-reviewer**: the UI gate already has build evidence; locate the build artifact to prepare install + launch
- **open-sim** skill: the user says "open the simulator" → Step 2 takes the build artifact and installs + launches
- Any caller that wants to install an already-built iOS Simulator app onto a simulator and run it

## Does not trigger

- The caller already got `APP_PATH` + `BUNDLE_ID` from the main agent / a previous step
- The project has no `.xcworkspace` (bare `.xcodeproj` or SPM-only) — this skill assumes a workspace path; the caller has to adapt on its own
- Running a macOS / device build (this skill assumes destination = `generic/platform=iOS Simulator`)
- No build has run yet — `xcodebuild -showBuildSettings` still runs without a build, but the `.app` does not actually exist; this skill reports `BUILD_ARTIFACT_NOT_FOUND` and lets the caller decide the next step

## Steps

### Step 1: locate the workspace

Walk up from cwd looking for a `.xcworkspace` folder (many projects keep it at the repo root, but a monorepo may have it in a subdirectory):

```bash
WORKSPACE_DIR="$(pwd)"
WORKSPACE_NAME=""
while [[ "$WORKSPACE_DIR" != "/" ]]; do
  # any .xcworkspace in the current directory
  found=$(find "$WORKSPACE_DIR" -maxdepth 1 -name '*.xcworkspace' -type d 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    WORKSPACE_NAME="$(basename "$found")"
    break
  fi
  WORKSPACE_DIR="$(dirname "$WORKSPACE_DIR")"
done
[[ -n "$WORKSPACE_NAME" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: no .xcworkspace ancestor"; exit 1; }
```

### Step 2: determine the scheme

The caller should pass the scheme name (e.g. `<YourApp>iOS` / `MyAppiOS`). If it did not:

```bash
# list every scheme in the workspace and let the caller pick
xcrun xcodebuild -workspace "$WORKSPACE_DIR/$WORKSPACE_NAME" -list 2>/dev/null | sed -n '/Schemes:/,$p'
```

Selection heuristic (when the caller did not specify):

- The repo root's `AGENTS.md` / `Justfile` names the main scheme → use it
- Prefer scheme names containing the `iOS` / `iphone` keyword
- Otherwise take the first entry, and note in the output "scheme auto-selected, may be wrong"

### Step 3: get build settings

```bash
SETTINGS=$(cd "$WORKSPACE_DIR" && xcodebuild -workspace "$WORKSPACE_NAME" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null)
```

Extract 3 fields:

```bash
BUILT_DIR=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR =/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME =/ {print $2; exit}')
BUNDLE_ID=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER =/ {print $2; exit}')
APP_PATH="$BUILT_DIR/$APP_NAME"
```

### Step 4: verify the `.app` actually exists

```bash
[[ -d "$APP_PATH" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: $APP_PATH does not exist — run just build-ios / Xcode build / xcodebuild build first"; exit 1; }
```

`-showBuildSettings` **returns a path** even before a build, while the `.app` does not actually exist. Verify it so the caller does not carry a nonexistent path into a failing `simctl install`.

### Step 5: get the simulator lease

```bash
SIM_OUT="$(bash "$HARNESS_ROOT/scripts/worktree-sim.sh" ensure)" || exit 1
SIMULATOR_UDID="$(printf '%s\n' "$SIM_OUT" | sed -n 's/^SIMULATOR_UDID=//p')"
[[ -n "$SIMULATOR_UDID" ]] || exit 1
```

Use `ensure --runtime <id>` for a separate lease on a specific runtime. If leasing fails, stop and report the error so the caller does not install on another checkout's device.

### Step 6: output

Print key-value lines for the caller to parse:

```bash
echo "APP_PATH=$APP_PATH"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "SIMULATOR_UDID=$SIMULATOR_UDID"
echo "WORKSPACE=$WORKSPACE_DIR/$WORKSPACE_NAME"
echo "SCHEME=$SCHEME"
```

## Error handling

| Failure | Error code | What the caller does |
|---|---|---|
| No `.xcworkspace` ancestor | `BUILD_ARTIFACT_NOT_FOUND: no .xcworkspace ancestor` | Caller checks whether cwd is inside the repo; bare xcodeproj / SPM-only projects use another route |
| `-showBuildSettings` returns empty / fields missing | `BUILD_ARTIFACT_NOT_FOUND: cannot parse build settings` | Usually a wrong scheme name; caller cross-checks with `xcodebuild -list` |
| `.app` does not exist | `BUILD_ARTIFACT_NOT_FOUND: <path> does not exist` | Caller returns `DEGRADED build_artifact_not_found`; do not add a build inside this skill |
| Simulator lease fails or returns no UDID | Stop before producing install inputs | Report the lease error to the caller |

**Do not** run `xcodebuild build` yourself to fill the gap — the build is the caller's / user's responsibility; this skill only locates the build artifact.
The lease helper boots the simulator. The caller installs and launches the app after boot completes.

## Caller integration examples

### UI reviewer

```
Skill(find-ios-build-artifact)   # input: scheme = <YourApp>iOS
# output: APP_PATH=/path/to/<YourApp>.app, BUNDLE_ID=<your.bundle.id>, SIMULATOR_UDID=A1B2-...

# build artifact fails → return DEGRADED build_artifact_not_found
# lease fails → report the simulator error
# success → simctl install $SIMULATOR_UDID $APP_PATH; simctl launch $SIMULATOR_UDID $BUNDLE_ID
```

### open-sim skill Step 2

```
Skill(find-ios-build-artifact)   # input: scheme = <YourApp>iOS
# failure → tell the user to "run just build-ios first"
# success → Step 3 installs + launches with $SIMULATOR_UDID (no sim picker for the user — the worktree is already bound)
```

## Out of scope

- ❌ **No build** — when nothing was built / the artifact does not exist, it only errors and lets the caller decide the next step
- ❌ **No scheme guessing** — the caller must pass one, or this skill lists the schemes for the caller to pick
- ❌ **No macOS / device handling** — destination is hardcoded to `generic/platform=iOS Simulator`
- ❌ **No installing / launching the app** — that is the caller's job (`simctl install/launch` or an mcp tool)
- ❌ **No caller-picked simulator** — the checkout's leased UDID is decided by `worktree-sim.sh ensure`; the caller does not pick another

## Why (core)

- The three fields (`APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID`) are emitted as one package — the caller gets everything install/launch needs in one go
- `SIMULATOR_UDID` comes from `worktree-sim.sh ensure`: lease and boot an existing iPhone so the device argument routes to the checkout's simulator
