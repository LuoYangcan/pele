#!/usr/bin/env bash
# Usage: worktree-sim.sh <ensure|shutdown|delete> [--runtime <runtime-id>]
#
# ensure   — lease the most recently used free existing iPhone simulator (iPad and legacy
#            sim-<slug> devices excluded) to this checkout, boot it, print SIMULATOR_UDID / SIM_NAME.
#            The same checkout keeps its device; another checkout can take it only after
#            cleanup, checkout removal, or 2 hours without ensure. Never creates a simulator.
# shutdown — release this worktree's leases; shut down legacy registered runtime variants
# delete   — release this worktree's leases; delete unshared legacy registered variants
#
# Leases live in ${XDG_STATE_HOME:-~/.local/state}/pele/simulator-leases.json.
# Legacy registrations are .claude/sim-udid[-<suffix>] files written by the per-worktree version.
#
# Optional flag:
#   --runtime <runtime-id>   ensure: lease a separate device on that runtime (e.g. iOS-18-6).
#                            shutdown/delete: restrict to that runtime's lease and legacy
#                            registration; <suffix> drops the dash after the platform (ios18-6).
#
# Exit codes:
#   0  success (or no-op for shutdown/delete when nothing is associated)
#   1  not a Git checkout (ensure) / linked worktree (cleanup), unresolved/shared association, or cleanup failure
#   2  no .xcworkspace under checkout root (ensure only; not an iOS project)
#   3  no free existing iPhone simulator matches (all leased, or none on the requested runtime)
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

# Git resolves the innermost checkout, including Claude/Codex and nested linked worktrees.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$ROOT" ]]; then
  echo "ERROR: not in a Git checkout: $PWD" >&2
  exit 1
fi
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/worktree-simulators.py"

case "$ACTION" in
  ensure)
    if ! find "$ROOT" -maxdepth 3 -name '*.xcworkspace' -type d 2>/dev/null | grep -q .; then
      echo "ERROR: no .xcworkspace under $ROOT (not an iOS project)" >&2
      exit 2
    fi
    args=(ensure --worktree "$ROOT")
    [[ -z "$RUNTIME_ARG" ]] || args+=(--runtime "$RUNTIME_ARG")
    exec python3 "$HELPER" "${args[@]}"
    ;;

  shutdown|delete)
    if [[ ! -f "$ROOT/.git" ]]; then
      echo "ERROR: not in a registered linked Git worktree: $PWD" >&2
      exit 1
    fi
    args=("$ACTION" --worktree "$ROOT")
    if [[ -n "$RUNTIME_ARG" ]]; then
      args+=(--suffix "$(echo "$RUNTIME_ARG" | tr '[:upper:]' '[:lower:]' | sed -E 's/^([a-z]+)-/\1/')")
    fi
    exec python3 "$HELPER" "${args[@]}"
    ;;

  *)
    echo "Usage: $(basename "$0") <ensure|shutdown|delete> [--runtime <runtime-id>]" >&2
    exit 64
    ;;
esac
