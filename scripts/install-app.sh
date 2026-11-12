#!/bin/bash
# Build iMessage Relay.app and copy it to ~/Applications. No sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="iMessage Relay"
DEST="${HOME}/Applications/${APP_NAME}.app"

"${ROOT}/scripts/build-app.sh"
mkdir -p "${HOME}/Applications"
rm -rf "${DEST}"
cp -R "${ROOT}/build/${APP_NAME}.app" "${DEST}"
echo "Installed ${DEST}"
open "${DEST}"
