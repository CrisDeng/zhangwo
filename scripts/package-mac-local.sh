#!/usr/bin/env bash
set -euo pipefail

# Local development build script for macOS app.
# Creates a universal binary with ad-hoc signing (no Apple Developer certificate required).
#
# Usage:
#   ./scripts/package-mac-local.sh
#
# Output:
#   - dist/<version>/掌握.app (or OpenClaw.app)
#   - dist/<version>/zhangwo-<version>.dmg (unstyled)

# Record start time for duration calculation
START_TIME=$(date +%s)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Ensure Node.js 22+ is available
if command -v nvm &>/dev/null; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm use 22 || nvm use node
elif ! command -v node &>/dev/null; then
  echo "Error: Node.js not found. Please install Node.js 22+ or nvm." >&2
  exit 1
fi

echo "🔧 Using Node.js $(node --version)"

# Build universal binary, skip team ID check for local builds
export BUILD_ARCHS="${BUILD_ARCHS:-all}"
export SKIP_TEAM_ID_CHECK=1

echo "📦 Building app bundle..."
"$ROOT_DIR/scripts/package-mac-app.sh"

# Get version and app path
VERSION=$(node -p "require('./scripts/version.json').version + '.' + require('./scripts/version.json').build")
APP_DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$ROOT_DIR/apps/macos/Sources/OpenClaw/Resources/Info.plist" 2>/dev/null || echo "OpenClaw")
APP_PATH="$ROOT_DIR/dist/$VERSION/${APP_DISPLAY_NAME}.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "🔏 Re-signing with ad-hoc signature..."
codesign --remove-signature "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"

echo "💿 Creating DMG (unstyled for speed)..."
export SKIP_DMG_STYLE=1
"$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH"

# Calculate and display total timing information
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
FINISH_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# Use pinyin name for DMG filename when app is 掌握
if [[ "$APP_DISPLAY_NAME" == "掌握" ]]; then
  DMG_NAME="zhangwo-${VERSION}.dmg"
else
  DMG_NAME="${APP_DISPLAY_NAME}-${VERSION}.dmg"
fi

echo ""
echo "=========================================="
echo "🎉 本地打包完成"
echo "📦 版本: $VERSION"
echo "📁 App: dist/$VERSION/${APP_DISPLAY_NAME}.app"
echo "💿 DMG: dist/$VERSION/$DMG_NAME"
echo "⏱  完成时间: $FINISH_TIME"
echo "⏱  总耗时: ${MINUTES}分${SECONDS}秒"
echo "=========================================="
