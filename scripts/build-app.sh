#!/bin/bash
# Build a Release .app bundle. Run this on the Mac that will execute the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="iMessage Relay"
APP="${ROOT}/build/${APP_NAME}.app"
IDENTIFIER="com.jamesalmeida.imessage-relay"

cd "${ROOT}"
swift build -c release --product imessage-relay

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp -f "${ROOT}/.build/release/imessage-relay" "${APP}/Contents/MacOS/imessage-relay"
chmod 755 "${APP}/Contents/MacOS/imessage-relay"
cp -f "${ROOT}/App/Info.plist" "${APP}/Contents/Info.plist"
cp -f "${ROOT}/App/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --identifier "${IDENTIFIER}" "${APP}/Contents/MacOS/imessage-relay"
  codesign --force --sign - --identifier "${IDENTIFIER}" "${APP}"
  echo "Ad-hoc signed ${APP} as ${IDENTIFIER}"
else
  echo "codesign not found; the bundle was assembled but not signed." >&2
  exit 1
fi

echo "Built ${APP}"
