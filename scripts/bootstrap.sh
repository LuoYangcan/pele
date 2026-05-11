#!/usr/bin/env bash
# Pele bootstrap — clone the repo into <pele-checkout> and run install.sh.
# Designed to be piped from curl:
#   curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/LuoYangCan/pele/main/scripts/bootstrap.sh | bash -s -- --apple --figma
#
# Defaults (override with env vars before piping):
#   <pele-checkout> = ~/Developer/pele       (PELE_INSTALL_DIR=<path>)
#   repo URL        = LuoYangCan/pele        (PELE_REPO_URL=<url>, e.g. your own fork)
#
# Any args after `--` are forwarded to install.sh.

set -euo pipefail

REPO_URL="${PELE_REPO_URL:-https://github.com/LuoYangCan/pele.git}"
DEST="${PELE_INSTALL_DIR:-${HOME}/Developer/pele}"

echo "[pele-bootstrap] repo: ${REPO_URL}"
echo "[pele-bootstrap] dest: ${DEST}"

if [ -d "$DEST/.git" ]; then
  echo "[pele-bootstrap] existing checkout found — pulling latest"
  git -C "$DEST" pull --ff-only
else
  mkdir -p "$(dirname "$DEST")"
  echo "[pele-bootstrap] cloning..."
  git clone --depth 1 "$REPO_URL" "$DEST"
fi

cd "$DEST"
exec ./install.sh "$@"
