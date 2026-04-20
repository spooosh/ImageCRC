#!/usr/bin/env bash
# Package ImageCRC.app into a distributable DMG via hdiutil.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ImageCRC"
APP="${APP_NAME}.app"
VOLNAME="${APP_NAME}"

if [ ! -d "${APP}" ]; then
    echo "✗ ${APP} not found. Build it first:"
    echo "    ./Scripts/make-app.sh"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
DMG="${APP_NAME}-${VERSION}.dmg"

echo "→ staging contents"
STAGING=$(mktemp -d -t imagecrc-dmg)
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

rm -f "${DMG}"

echo "→ hdiutil create ${DMG}"
hdiutil create \
    -volname "${VOLNAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG}" >/dev/null

SIZE=$(du -h "${DMG}" | cut -f1)
echo "✓ Built ${DMG} (${SIZE})"
