#!/usr/bin/env bash
# Usage: worktree-sim.sh <ensure|shutdown|delete> [--runtime <runtime-id>]
#
# ensure   — read-or-create per-worktree sim, ensure booted, print SIMULATOR_UDID / SIM_NAME
# shutdown — shutdown but keep the sim device
# delete   — shutdown + delete + drop UDID registration file
#
# Optional flag:
#   --runtime <runtime-id>   Pin sim to a specific iOS runtime (e.g. iOS-18-6).
#                            When set: SIM_NAME=sim-<slug>-<suffix>, UDID file=.claude/sim-udid-<suffix>.
#                            <suffix> = lowercase runtime-id with "ios-" prefix stripped and "-" preserved
#                            (iOS-18-6 → ios18-6; iOS-18-0 → ios18-0).
#                            Without the flag, behavior is identical to the pre-flag version.
#
# Exit codes:
#   0  success (or no-op for shutdown/delete when no sim registered)
#   1  not in a worktree (.worktrees/<slug> ancestor missing)
#   2  no .xcworkspace under worktree root (ensure only; not an iOS project)
#   3  simctl operation failed / requested runtime not installed
#  64  usage error

set -uo pipefail

ACTION="${1:-}"
shift || true

RUNTIME_ARG=""
while (($#)); do
  case "$1" in
    --runtime)
      RUNTIME_ARG="${2:-}"
      if [[ -z "$RUNTIME_ARG" ]]; then
        echo "ERROR: --runtime requires a value (e.g. iOS-18-6)" >&2
        exit 64
      fi
      shift 2
      ;;
    --runtime=*)
      RUNTIME_ARG="${1#--runtime=}"
      if [[ -z "$RUNTIME_ARG" ]]; then
        echo "ERROR: --runtime requires a value (e.g. iOS-18-6)" >&2
        exit 64
      fi
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Usage: $(basename "$0") <ensure|shutdown|delete> [--runtime <runtime-id>]" >&2
      exit 64
      ;;
  esac
done

worktree_root() {
  python3 - <<'PY'
import os
parts = os.getcwd().split(os.sep)
for i, part in enumerate(parts):
    if part == ".worktrees" and i + 1 < len(parts):
        print(os.sep.join(parts[: i + 2]))
        break
PY
}

WT_ROOT="$(worktree_root)"
if [[ -z "$WT_ROOT" ]]; then
  echo "ERROR: not in a worktree (no .worktrees/<slug> ancestor of $PWD)" >&2
  exit 1
fi

SLUG="$(basename "$WT_ROOT")"

# Derive runtime-scoped names. Without --runtime, both fall back to the
# original (no-suffix) form, so existing callers see no behavior change.
if [[ -n "$RUNTIME_ARG" ]]; then
  # Normalize "iOS-18-6" → "ios18-6" (lowercase + drop the dash after the platform prefix).
  # We keep the minor digit to disambiguate sibling runtimes (iOS-18-0 vs iOS-18-6).
  RUNTIME_SUFFIX="$(echo "$RUNTIME_ARG" | tr '[:upper:]' '[:lower:]' | sed -E 's/^([a-z]+)-/\1/')"
  if [[ -z "$RUNTIME_SUFFIX" ]]; then
    echo "ERROR: cannot derive runtime suffix from --runtime $RUNTIME_ARG" >&2
    exit 64
  fi
  SIM_NAME="sim-${SLUG}-${RUNTIME_SUFFIX}"
  SIM_UDID_FILE="$WT_ROOT/.claude/sim-udid-${RUNTIME_SUFFIX}"
  RUNTIME_IDENTIFIER="com.apple.CoreSimulator.SimRuntime.${RUNTIME_ARG}"
else
  RUNTIME_SUFFIX=""
  SIM_NAME="sim-${SLUG}"
  SIM_UDID_FILE="$WT_ROOT/.claude/sim-udid"
  RUNTIME_IDENTIFIER=""
fi

simctl_device_exists() {
  local target="$1"
  xcrun simctl list devices -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for _, devs in data['devices'].items():
    for d in devs:
        if d.get('udid') == '$target':
            sys.exit(0)
sys.exit(1)
"
}

simctl_lookup_by_name() {
  xcrun simctl list devices -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for _, devs in data['devices'].items():
    for d in devs:
        if d.get('name') == '$SIM_NAME':
            print(d['udid']); sys.exit()
"
}

# Return 0 if RUNTIME_IDENTIFIER is installed + available; else print guidance and return 3.
verify_requested_runtime() {
  local installed
  installed="$(xcrun simctl list runtimes -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['runtimes']:
    if r.get('identifier') == '$RUNTIME_IDENTIFIER' and r.get('isAvailable'):
        print('yes'); sys.exit()
")"
  if [[ "$installed" != "yes" ]]; then
    echo "ERROR: requested runtime '$RUNTIME_ARG' (identifier '$RUNTIME_IDENTIFIER') is not installed or not available." >&2
    echo "       Install via: Xcode → Settings → Platforms → '+', or:" >&2
    echo "         xcodebuild -downloadPlatform iOS  # then pick the version" >&2
    echo "       Check current runtimes with: xcrun simctl list runtimes" >&2
    return 3
  fi
  return 0
}

case "$ACTION" in
  ensure)
    if ! find "$WT_ROOT" -maxdepth 3 -name '*.xcworkspace' -type d 2>/dev/null | grep -q .; then
      echo "ERROR: no .xcworkspace under $WT_ROOT (not an iOS project)" >&2
      exit 2
    fi

    UDID=""
    if [[ -f "$SIM_UDID_FILE" ]]; then
      UDID="$(cat "$SIM_UDID_FILE")"
      if [[ -n "$UDID" ]] && ! simctl_device_exists "$UDID"; then
        UDID=""
        rm -f "$SIM_UDID_FILE"
      fi
    fi

    if [[ -z "$UDID" ]]; then
      UDID="$(simctl_lookup_by_name)"
    fi

    if [[ -z "$UDID" ]]; then
      # Resolve target runtime first — needed for device-type compatibility filtering.
      if [[ -n "$RUNTIME_ARG" ]]; then
        verify_requested_runtime || exit 3
        RUNTIME="$RUNTIME_IDENTIFIER"
      else
        RUNTIME="$(xcrun simctl list runtimes -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
ios = [r for r in data['runtimes'] if r.get('platform') == 'iOS' and r.get('isAvailable')]
def ver(r):
    v = r.get('version', '0.0').split('.')
    return tuple(int(p) for p in v if p.isdigit()) or (0,)
ios.sort(key=ver, reverse=True)
print(ios[0]['identifier'] if ios else '')
")"
        if [[ -z "$RUNTIME" ]]; then
          echo "ERROR: no available iOS runtime via 'xcrun simctl list runtimes'" >&2
          exit 3
        fi
      fi

      OVERRIDE_FILE="$WT_ROOT/.claude/sim-device-type"
      if [[ -f "$OVERRIDE_FILE" ]]; then
        DEVICE_TYPE="$(head -1 "$OVERRIDE_FILE" | tr -d '\n\r')"
      else
        # Pick a device type compatible with $RUNTIME. Older iOS runtimes (e.g. iOS 18)
        # don't support newer hardware (iPhone 17 family), so we intersect the catalog
        # with the runtime's supportedDeviceTypes when available.
        DEVICE_TYPE="$(xcrun simctl list runtimes -j 2>/dev/null | RUNTIME_ID="$RUNTIME" python3 -c "
import json, os, re, subprocess, sys
runtimes = json.load(sys.stdin)
target_id = os.environ.get('RUNTIME_ID', '')
supported_ids = set()
for r in runtimes['runtimes']:
    if r.get('identifier') == target_id:
        for d in r.get('supportedDeviceTypes', []):
            ident = d.get('identifier')
            if ident:
                supported_ids.add(ident)
        break
dt_raw = subprocess.run(['xcrun', 'simctl', 'list', 'devicetypes', '-j'],
                        capture_output=True, text=True).stdout
dt_data = json.loads(dt_raw)
devicetypes = dt_data.get('devicetypes', [])
if supported_ids:
    devicetypes = [dt for dt in devicetypes if dt.get('identifier') in supported_ids]
candidates = []
for dt in devicetypes:
    name = dt.get('name', '')
    m = re.match(r'iPhone (\d+) Pro$', name)
    if m:
        candidates.append((int(m.group(1)), name))
if not candidates:
    for dt in devicetypes:
        name = dt.get('name', '')
        if 'iPhone' in name and 'Pro' in name and 'Max' not in name:
            candidates.append((0, name))
if not candidates:
    for dt in devicetypes:
        name = dt.get('name', '')
        if 'iPhone' in name and not any(s in name for s in ('Max','Plus','mini','SE')):
            candidates.append((0, name))
candidates.sort(key=lambda x: -x[0])
print(candidates[0][1] if candidates else '')
")"
      fi
      if [[ -z "$DEVICE_TYPE" ]]; then
        echo "ERROR: no suitable iPhone device type found for runtime $RUNTIME via 'xcrun simctl list devicetypes'" >&2
        exit 3
      fi

      if ! UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME" 2>&1)"; then
        echo "ERROR: simctl create failed: $UDID" >&2
        exit 3
      fi
    fi

    mkdir -p "$WT_ROOT/.claude"
    echo "$UDID" > "$SIM_UDID_FILE"

    BOOT_OUT="$(xcrun simctl boot "$UDID" 2>&1 || true)"
    if [[ -n "$BOOT_OUT" ]] && ! echo "$BOOT_OUT" | grep -qiE 'booted|already'; then
      echo "WARN: simctl boot: $BOOT_OUT" >&2
    fi

    echo "SIMULATOR_UDID=$UDID"
    echo "SIM_NAME=$SIM_NAME"
    ;;

  shutdown)
    if [[ ! -f "$SIM_UDID_FILE" ]]; then
      echo "no sim registered for $SLUG${RUNTIME_SUFFIX:+ (runtime $RUNTIME_ARG)}"
      exit 0
    fi
    UDID="$(cat "$SIM_UDID_FILE")"
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    echo "shutdown $SIM_NAME ($UDID)"
    ;;

  delete)
    if [[ "$PWD" == *"/.worktrees/$SLUG/.subworktrees/"* ]]; then
      echo "ERROR: refusing to delete main worktree sim from a sub-worktree cwd" >&2
      echo "       cd back to .worktrees/$SLUG first if you really want to delete it." >&2
      exit 1
    fi
    if [[ ! -f "$SIM_UDID_FILE" ]]; then
      echo "no sim registered for $SLUG${RUNTIME_SUFFIX:+ (runtime $RUNTIME_ARG)}"
      exit 0
    fi
    UDID="$(cat "$SIM_UDID_FILE")"
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID" 2>/dev/null || true
    rm -f "$SIM_UDID_FILE"
    echo "deleted $SIM_NAME ($UDID)"
    ;;

  *)
    echo "Usage: $(basename "$0") <ensure|shutdown|delete> [--runtime <runtime-id>]" >&2
    exit 64
    ;;
esac
