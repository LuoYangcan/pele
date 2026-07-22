#!/bin/bash
# Pre-seed Claude Code folder trust for a directory, so the startup
# "Quick safety check / trust this folder?" dialog doesn't appear.
# Usage: trust-dir.sh <dir> [<dir> ...]   (defaults to $PWD)
# Run BEFORE launching `claude` in that directory (edits made while a
# session is running may be clobbered when that session saves state).
set -euo pipefail

CONFIG="$HOME/.claude.json"
[[ -f "$CONFIG" ]] || { echo "no $CONFIG" >&2; exit 1; }

dirs=("${@:-$PWD}")

python3 - "$CONFIG" "${dirs[@]}" <<'PY'
import json, os, sys

config_path = sys.argv[1]
dirs = [os.path.realpath(d) for d in sys.argv[2:]]

with open(config_path) as f:
    data = json.load(f)

projects = data.setdefault("projects", {})
for d in dirs:
    entry = projects.setdefault(d, {})
    if entry.get("hasTrustDialogAccepted") and entry.get("hasCompletedProjectOnboarding"):
        print(f"already trusted: {d}")
        continue
    entry["hasTrustDialogAccepted"] = True
    entry["hasCompletedProjectOnboarding"] = True
    entry.setdefault("allowedTools", [])
    print(f"trusted: {d}")

tmp = config_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, config_path)
PY
