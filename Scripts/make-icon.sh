#!/usr/bin/env bash
# Build Resources/AppIcon.icns from a 1024×1024 master PNG.
#
# Usage:
#   ./Scripts/make-icon.sh [SOURCE_PNG] [OUTPUT_ICNS]
#
# Defaults:
#   SOURCE_PNG   = Resources/AppIcon-master.png
#   OUTPUT_ICNS  = Resources/AppIcon.icns
#
# The master PNG must already contain the macOS squircle on a transparent
# background — .icns is NOT auto-masked by the system like iOS icons are.
#
# Set FORCE=1 to bypass the dimension check (not recommended; downscales
# from non-1024 sources will be blurry at small sizes).
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="${1:-Resources/AppIcon-master.png}"
OUT_ICNS="${2:-Resources/AppIcon.icns}"

if [ ! -f "${SRC}" ]; then
    echo "✗ source not found: ${SRC}" >&2
    echo "  usage: $0 [SOURCE_PNG] [OUTPUT_ICNS]" >&2
    exit 1
fi

W=$(sips -g pixelWidth  "${SRC}" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "${SRC}" | awk '/pixelHeight/{print $2}')

if [ "${W}" != "1024" ] || [ "${H}" != "1024" ]; then
    echo "⚠ source is ${W}×${H}, expected 1024×1024" >&2
    if [ -z "${FORCE:-}" ]; then
        echo "  re-run with FORCE=1 to proceed anyway" >&2
        exit 1
    fi
fi

WORK_DIR="$(mktemp -d)"
ICONSET_DIR="${WORK_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT

gen() {
    local size=$1 name=$2
    sips -z "${size}" "${size}" "${SRC}" --out "${ICONSET_DIR}/${name}" >/dev/null
    printf "  → %-26s %d×%d\n" "${name}" "${size}" "${size}"
}

echo "→ rendering iconset from ${SRC}"
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png

# 1024×1024 slot = source as-is (no resample), unless source was overridden via FORCE.
if [ "${W}" = "1024" ] && [ "${H}" = "1024" ]; then
    cp "${SRC}" "${ICONSET_DIR}/icon_512x512@2x.png"
    printf "  → %-26s %s (copied)\n" "icon_512x512@2x.png" "1024×1024"
else
    gen 1024 icon_512x512@2x.png
fi

mkdir -p "$(dirname "${OUT_ICNS}")"
iconutil -c icns "${ICONSET_DIR}" -o "${OUT_ICNS}"

SIZE=$(du -h "${OUT_ICNS}" | cut -f1)
echo "✓ wrote ${OUT_ICNS} (${SIZE})"
