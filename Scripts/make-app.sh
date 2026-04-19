#!/usr/bin/env bash
# Build ImageCRC with Swift Package Manager and assemble a native .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
APP_NAME="ImageCRC"
BUNDLE_ID="com.spooosh.image-crc"
VERSION="0.1.0"
BUILD="1"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH=$(swift build -c "${CONFIG}" --show-bin-path)
EXE="${BIN_PATH}/${APP_NAME}"

if [ ! -x "${EXE}" ]; then
    echo "Executable not found at ${EXE}"
    exit 1
fi

APP="${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "${EXE}" "${APP}/Contents/MacOS/${APP_NAME}"

# Ensure SPM resource bundles (e.g. libwebp) ship inside the .app
if ls "${BIN_PATH}"/*.bundle > /dev/null 2>&1; then
    cp -R "${BIN_PATH}"/*.bundle "${APP}/Contents/Resources/" || true
fi

# Bundle pngquant for PNG lossy compression. We look up via brew first, then PATH.
PNGQUANT_SRC=""
if command -v brew >/dev/null 2>&1 && brew --prefix pngquant >/dev/null 2>&1; then
    PNGQUANT_SRC="$(brew --prefix pngquant)/bin/pngquant"
elif command -v pngquant >/dev/null 2>&1; then
    PNGQUANT_SRC="$(command -v pngquant)"
fi

if [ -n "${PNGQUANT_SRC}" ] && [ -x "${PNGQUANT_SRC}" ]; then
    mkdir -p "${APP}/Contents/Resources/bin"
    cp "${PNGQUANT_SRC}" "${APP}/Contents/Resources/bin/pngquant"
    chmod +x "${APP}/Contents/Resources/bin/pngquant"
    echo "→ bundled $(${PNGQUANT_SRC} --version 2>&1 | head -1)"
else
    echo "⚠ pngquant not found — PNG lossy compression will fail at runtime."
    echo "  Install via: brew install pngquant"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>ImageCRC</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 spooosh</string>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
</dict>
</plist>
PLIST

echo "→ ad-hoc codesign"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || codesign --force --sign - "${APP}"

echo "✓ Built ${APP}"
