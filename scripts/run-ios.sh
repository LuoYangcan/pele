#!/usr/bin/env bash
# Usage: run-ios.sh --target <sim|device> [--device-id <id>] [--no-build] [--derived <path>]
#
# Build the iOS app, then install + launch the resulting `.app` on either this
# worktree's session Simulator (--target sim) or a connected real device
# (--target device), and print a structured result block (TARGET / WHERE / UDID /
# APP_PATH / BUNDLE_ID / PID).
#
# Shared back-end for the `open-sim` and `run-device` skills. The skill layer is a
# thin wrapper; this script owns the deterministic build -> locate -> install ->
# launch orchestration, so the calling agent only runs one command and relays the
# summary (a cheap model is enough; the big xcodebuild log stays on this side).
#
# ── Project config (env vars — override per project) ──────────────────────────
#   RUN_IOS_BUILD_CMD  Build command (word-split on spaces). Default: "just build-ios".
#                      Must build a Debug simulator app by default; for --target device
#                      it is run with the destination env below prefixed.
#                      e.g. RUN_IOS_BUILD_CMD="xcodebuild -scheme MyApp -configuration Debug \
#                           -derivedDataPath build/DerivedData -destination ... build"
#   RUN_IOS_DEST_ENV   (device target only) Name of the env var your build command reads
#                      for the iOS destination. The script runs it as
#                      `env "$RUN_IOS_DEST_ENV=platform=iOS,id=<id>" $RUN_IOS_BUILD_CMD`.
#                      Required for --target device (no universal default). e.g. a justfile
#                      that does `-destination "$(env_var_or_default("IOS_DEST", ...))"`
#                      → set RUN_IOS_DEST_ENV=IOS_DEST.
#   RUN_IOS_DERIVED    DerivedData dir relative to project root. Default: "build/DerivedData".
#                      Products are read from <root>/<derived>/Build/Products/Debug-iphone{os,simulator}.
#
# Flags:
#   --target sim      Install on the per-worktree sim via `~/.claude/scripts/worktree-sim.sh`
#                     (optional helper — if absent, falls back to a booted / newest available
#                     iPhone), then brings the Simulator window to front.
#   --target device   Install on a connected real device via devicectl. Auto-picks the single
#                     paired device; with >1 paired you must pass --device-id.
#   --device-id <id>  CoreDevice identifier (the UUID `identifier` field of
#                     `xcrun devicectl list devices`). device target only.
#   --no-build        Skip the build; install the existing artifact as-is.
#   --derived <path>  Override RUN_IOS_DERIVED for this run.
#
# On ANY step failure: print a clear error and exit non-zero. Never auto-retry / auto-fix.
#
# Exit codes:
#   0  success
#   1  usage / precondition error (bad args, no project root, no/ambiguous device, missing config)
#   2  build failed
#   3  artifact (.app / bundle id) not found
#   4  install / launch failed

set -uo pipefail

TARGET=""
DEVICE_ID=""
NO_BUILD=0
BUILD_CMD="${RUN_IOS_BUILD_CMD:-just build-ios}"
DEST_ENV="${RUN_IOS_DEST_ENV:-}"
DERIVED="${RUN_IOS_DERIVED:-build/DerivedData}"
DEV_NAME=""
DEV_STATE=""
SIM_NAME=""
UDID=""
PID=""

while (($#)); do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --device-id) DEVICE_ID="${2:-}"; shift 2 ;;
    --device-id=*) DEVICE_ID="${1#--device-id=}"; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --derived) DERIVED="${2:-}"; shift 2 ;;
    --derived=*) DERIVED="${1#--derived=}"; shift ;;
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$TARGET" in
  sim | device) : ;;
  *) echo "ERROR: --target must be 'sim' or 'device'" >&2; exit 1 ;;
esac

# ── project root: git toplevel (covers worktrees), else nearest justfile ancestor ──
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  ROOT="$PWD"
  while [[ "$ROOT" != "/" ]]; do
    [[ -f "$ROOT/justfile" || -f "$ROOT/Justfile" ]] && break
    ROOT="$(dirname "$ROOT")"
  done
fi
[[ -n "$ROOT" && -d "$ROOT" ]] || {
  echo "ERROR: cannot resolve project root — run this inside the iOS repo / worktree." >&2
  exit 1
}

# ── device target: resolve the CoreDevice identifier BEFORE build (destination needs it) ──
if [[ "$TARGET" == device ]]; then
  if [[ -z "$DEST_ENV" ]]; then
    echo "ERROR: --target device needs RUN_IOS_DEST_ENV set — the name of the env var your build" >&2
    echo "       command reads for the iOS destination (e.g. RUN_IOS_DEST_ENV=IOS_DEST)." >&2
    exit 1
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    DVC_JSON="$(mktemp)"
    if ! xcrun devicectl list devices --json-output "$DVC_JSON" >/dev/null 2>&1; then
      echo "ERROR: 'xcrun devicectl list devices' failed — is Xcode / CoreDevice ready?" >&2
      rm -f "$DVC_JSON"
      exit 1
    fi
    PICK="$(python3 - "$DVC_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
devs = [x for x in data.get('result', {}).get('devices', [])
        if x.get('connectionProperties', {}).get('pairingState') == 'paired']
def row(x):
    return "\t".join([
        x.get('identifier', ''),
        x.get('deviceProperties', {}).get('name', ''),
        x.get('connectionProperties', {}).get('tunnelState', ''),
    ])
if len(devs) == 1:
    print("OK")
    print(row(devs[0]))
elif not devs:
    print("NONE")
else:
    print("MANY")
    for x in devs:
        print(row(x))
PY
)"
    rm -f "$DVC_JSON"
    HEAD="$(printf '%s\n' "$PICK" | head -1)"
    if [[ "$HEAD" == NONE ]]; then
      echo "ERROR: no paired iPhone found. Plug in + unlock + trust a device, or pass --device-id <id>." >&2
      echo "       List devices: xcrun devicectl list devices" >&2
      exit 1
    elif [[ "$HEAD" == MANY ]]; then
      echo "ERROR: multiple paired devices — pass --device-id <id> (the CoreDevice 'identifier' UUID):" >&2
      printf '%s\n' "$PICK" | tail -n +2 | while IFS=$'\t' read -r ident name state; do
        echo "         $ident  $name  ($state)" >&2
      done
      exit 1
    else
      LINE="$(printf '%s\n' "$PICK" | sed -n '2p')"
      DEVICE_ID="$(printf '%s' "$LINE" | cut -f1)"
      DEV_NAME="$(printf '%s' "$LINE" | cut -f2)"
      DEV_STATE="$(printf '%s' "$LINE" | cut -f3)"
      echo ">> device: ${DEV_NAME:-$DEVICE_ID} ($DEVICE_ID) [$DEV_STATE]" >&2
      [[ "$DEV_STATE" == connected ]] ||
        echo "WARN: device tunnelState='$DEV_STATE' (not 'connected') — build/install may fail if it's unplugged or locked." >&2
    fi
  fi
fi

# ── build ──
if [[ "$NO_BUILD" == 0 ]]; then
  echo ">> build (target=$TARGET): $BUILD_CMD" >&2
  if [[ "$TARGET" == device ]]; then
    # shellcheck disable=SC2086  # $BUILD_CMD is a command, intentionally word-split
    if ! (cd "$ROOT" && env "$DEST_ENV=platform=iOS,id=$DEVICE_ID" $BUILD_CMD); then
      echo "ERROR: device build failed — device plugged in + unlocked + trusted? signing configured?" >&2
      exit 2
    fi
  else
    # shellcheck disable=SC2086  # $BUILD_CMD is a command, intentionally word-split
    if ! (cd "$ROOT" && $BUILD_CMD); then
      echo "ERROR: simulator build failed (see xcodebuild output above)." >&2
      exit 2
    fi
  fi
fi

# ── locate artifact (read bundle id straight from the built .app — project-agnostic) ──
if [[ "$TARGET" == device ]]; then
  PRODUCTS="$ROOT/$DERIVED/Build/Products/Debug-iphoneos"
else
  PRODUCTS="$ROOT/$DERIVED/Build/Products/Debug-iphonesimulator"
fi
APP_PATH="$(ls -dt "$PRODUCTS"/*.app 2>/dev/null | grep -vEi '(Tests?|UITests|Runner)\.app$' | head -1)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: no .app in $PRODUCTS." >&2
  [[ "$NO_BUILD" == 1 ]] && echo "       Drop --no-build to build first." >&2
  exit 3
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null)"
[[ -n "$BUNDLE_ID" ]] || {
  echo "ERROR: cannot read CFBundleIdentifier from $APP_PATH/Info.plist" >&2
  exit 3
}

# ── install + launch ──
if [[ "$TARGET" == device ]]; then
  echo ">> devicectl install + launch on ${DEV_NAME:-$DEVICE_ID}..." >&2
  if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
    echo "ERROR: devicectl install failed — device plugged in + unlocked + trusted?" >&2
    exit 4
  fi
  if ! LAUNCH_OUT="$(xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1)"; then
    echo "ERROR: devicectl launch failed:" >&2
    printf '%s\n' "$LAUNCH_OUT" >&2
    exit 4
  fi
  PID="$(printf '%s\n' "$LAUNCH_OUT" | grep -oiE 'process [0-9]+|identifier[: ]*[0-9]+' | grep -oE '[0-9]+' | tail -1)"
  WHERE="device:${DEV_NAME:-$DEVICE_ID}"
  UDID_OUT="$DEVICE_ID"
else
  # Optional helper: per-worktree sim isolation. Absent / non-worktree → graceful fallback.
  SIM_OUT="$(bash "$HOME/.claude/scripts/worktree-sim.sh" ensure 2>/dev/null)" && {
    UDID="$(printf '%s\n' "$SIM_OUT" | awk -F= '/^SIMULATOR_UDID=/{print $2}')"
    SIM_NAME="$(printf '%s\n' "$SIM_OUT" | awk -F= '/^SIM_NAME=/{print $2}')"
  } || UDID=""

  if [[ -z "$UDID" ]]; then
    # fallback: booted iPhone first, else newest available iPhone + boot.
    UDID="$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for _, devs in data['devices'].items():
    for d in devs:
        if d.get('state') == 'Booted' and 'iPhone' in d.get('name', ''):
            print(d['udid']); sys.exit()
")"
    if [[ -z "$UDID" ]]; then
      UDID="$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import json, re, sys
data = json.load(sys.stdin)
def ver(rt):
    m = re.search(r'iOS-(\d+)-(\d+)', rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
cands = []
for rt, devs in data['devices'].items():
    if 'iOS' not in rt:
        continue
    for d in devs:
        if 'iPhone' in d.get('name', ''):
            cands.append((ver(rt), d['udid']))
cands.sort(key=lambda x: (-x[0][0], -x[0][1]))
print(cands[0][1] if cands else '')
")"
      [[ -n "$UDID" ]] || {
        echo "ERROR: no iPhone simulator available — install an iOS runtime in Xcode > Settings > Platforms." >&2
        exit 4
      }
      xcrun simctl boot "$UDID" 2>/dev/null || true
    fi
    SIM_NAME="$(xcrun simctl list devices -j 2>/dev/null | UDID="$UDID" python3 -c "
import json, os, sys
data = json.load(sys.stdin)
target = os.environ['UDID']
for _, devs in data['devices'].items():
    for d in devs:
        if d.get('udid') == target:
            print(d.get('name', '')); sys.exit()
")"
  fi

  echo ">> simctl install + launch on ${SIM_NAME:-$UDID}..." >&2
  if ! xcrun simctl install "$UDID" "$APP_PATH"; then
    echo "ERROR: simctl install failed — is this a simulator build (Debug-iphonesimulator)?" >&2
    exit 4
  fi
  if ! LAUNCH_OUT="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1)"; then
    echo "ERROR: simctl launch failed:" >&2
    printf '%s\n' "$LAUNCH_OUT" >&2
    exit 4
  fi
  PID="$(printf '%s\n' "$LAUNCH_OUT" | grep -oE '[0-9]+' | tail -1)"
  open -a Simulator
  WHERE="sim:${SIM_NAME:-$UDID}"
  UDID_OUT="$UDID"
fi

# ── result ──
echo ""
echo "----- run-ios result -----"
echo "TARGET=$TARGET"
echo "WHERE=$WHERE"
echo "UDID=$UDID_OUT"
echo "APP_PATH=$APP_PATH"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "PID=${PID:-?}"
echo "--------------------------"
echo "✅ launched $BUNDLE_ID on $WHERE (pid ${PID:-?})"
