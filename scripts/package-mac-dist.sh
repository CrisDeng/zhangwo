#!/usr/bin/env bash
set -euo pipefail

# Record start time for duration calculation
DIST_START_TIME=$(date +%s)

# Build the mac app bundle, then create a zip (Sparkle) + styled DMG (humans).
#
# Output:
# - dist/<version>/OpenClaw.app (or 掌握.app)
# - dist/<version>/OpenClaw-<version>.zip
# - dist/<version>/OpenClaw-<version>.dmg

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Default to universal binary for distribution builds (supports both Apple Silicon and Intel Macs)
export BUILD_ARCHS="${BUILD_ARCHS:-all}"

"$ROOT_DIR/scripts/package-mac-app.sh"

# Read display name from Info.plist (e.g. "掌握"), fallback to "OpenClaw"
APP_DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$ROOT_DIR/apps/macos/Sources/OpenClaw/Resources/Info.plist" 2>/dev/null || echo "OpenClaw")

# Read version from version.json (already updated by package-mac-app.sh)
VERSION_FILE="$ROOT_DIR/scripts/version.json"
BASE_VERSION=$(node -p "require('$VERSION_FILE').version" 2>/dev/null || echo "0.0.1")
BUILD_NUM=$(node -p "require('$VERSION_FILE').build" 2>/dev/null || echo "1")
VERSION="$BASE_VERSION.$BUILD_NUM"

# Versioned output directory
VERSION_DIR="$ROOT_DIR/dist/$VERSION"
APP="$VERSION_DIR/${APP_DISPLAY_NAME}.app"

if [[ ! -d "$APP" ]]; then
  echo "Error: missing app bundle at $APP" >&2
  exit 1
fi

# Use pinyin name for distribution files when app is 掌握
if [[ "$APP_DISPLAY_NAME" == "掌握" ]]; then
  DIST_NAME="zhangwo"
else
  DIST_NAME="$APP_DISPLAY_NAME"
fi

ZIP="$VERSION_DIR/${DIST_NAME}-$VERSION.zip"
DMG="$VERSION_DIR/${DIST_NAME}-$VERSION.dmg"
NOTARY_ZIP="$VERSION_DIR/${DIST_NAME}-$VERSION.notary.zip"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
NOTARIZE=1

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  NOTARIZE=0
fi

if [[ "$NOTARIZE" == "1" ]]; then
  echo "📦 Notary zip: $NOTARY_ZIP"
  rm -f "$NOTARY_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
  STAPLE_APP_PATH="$APP" "$ROOT_DIR/scripts/notarize-mac-artifact.sh" "$NOTARY_ZIP"
  rm -f "$NOTARY_ZIP"
fi

echo "📦 Zip: $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "💿 DMG: $DMG"
"$ROOT_DIR/scripts/create-dmg.sh" "$APP" "$DMG"

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "🔏 Signing DMG: $DMG"
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  fi
  "$ROOT_DIR/scripts/notarize-mac-artifact.sh" "$DMG"
fi

# Calculate and display total timing information
DIST_END_TIME=$(date +%s)
DIST_DURATION=$((DIST_END_TIME - DIST_START_TIME))
DIST_MINUTES=$((DIST_DURATION / 60))
DIST_SECONDS=$((DIST_DURATION % 60))
DIST_FINISH_TIME=$(date "+%Y-%m-%d %H:%M:%S")

echo ""
echo "=========================================="
echo "🎉 完整打包流程已完成"
echo "📦 版本: $VERSION"
echo "📁 输出目录: $VERSION_DIR"
echo "⏱  完成时间: $DIST_FINISH_TIME"
echo "⏱  总耗时: ${DIST_MINUTES}分${DIST_SECONDS}秒"
echo "=========================================="
