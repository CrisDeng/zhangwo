#!/usr/bin/env bash
set -euo pipefail

# Record start time for duration calculation
START_TIME=$(date +%s)

# Create a styled DMG containing the app bundle + /Applications symlink.
#
# Usage:
#   scripts/create-dmg.sh <app_path> [output_dmg]
#
# Env:
#   DMG_VOLUME_NAME        default: CFBundleName (or "OpenClaw")
#   DMG_BACKGROUND_PATH    default: assets/dmg-background.png
#   DMG_BACKGROUND_SMALL   default: assets/dmg-background-small.png (recommended)
#   DMG_WINDOW_BOUNDS      default: "400 100 900 420" (500x320)
#   DMG_ICON_SIZE          default: 128
#   DMG_APP_POS            default: "125 160"
#   DMG_APPS_POS           default: "375 160"
#   SKIP_DMG_STYLE=1       skip Finder styling
#   DMG_EXTRA_SECTORS      extra sectors to keep when shrinking RW image (default: 2048)

APP_PATH="${1:-}"
OUT_PATH="${2:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <app_path> [output_dmg]" >&2
  exit 1
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App not found: $APP_PATH" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/dist"

APP_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "OpenClaw")
APP_BUNDLE_NAME=$(basename "$APP_PATH")  # e.g. "掌握.app" - actual folder name
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")

# Create versioned output directory
VERSION_DIR="$BUILD_DIR/$VERSION"
mkdir -p "$VERSION_DIR"

# Use pinyin name for DMG filename when app is 掌握
if [[ "$APP_NAME" == "掌握" ]]; then
  DMG_NAME="zhangwo-${VERSION}.dmg"
else
  DMG_NAME="${APP_NAME}-${VERSION}.dmg"
fi
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME}"
DMG_BACKGROUND_SMALL="${DMG_BACKGROUND_SMALL:-$ROOT_DIR/assets/dmg-background-small.png}"
DMG_BACKGROUND_PATH="${DMG_BACKGROUND_PATH:-$ROOT_DIR/assets/dmg-background.png}"

DMG_WINDOW_BOUNDS="${DMG_WINDOW_BOUNDS:-400 100 900 420}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-128}"
DMG_APP_POS="${DMG_APP_POS:-125 160}"
DMG_APPS_POS="${DMG_APPS_POS:-375 160}"
DMG_LICENSE_POS="${DMG_LICENSE_POS:-250 280}"
DMG_EXTRA_SECTORS="${DMG_EXTRA_SECTORS:-2048}"

to_applescript_list4() {
  local raw="$1"
  echo "$raw" | awk '{ printf "%s, %s, %s, %s", $1, $2, $3, $4 }'
}

to_applescript_pair() {
  local raw="$1"
  echo "$raw" | awk '{ printf "%s, %s", $1, $2 }'
}

if [[ -z "$OUT_PATH" ]]; then
  OUT_PATH="$VERSION_DIR/$DMG_NAME"
fi

echo "Creating DMG: $OUT_PATH"

# Cleanup stuck volumes.
for vol in "/Volumes/$DMG_VOLUME_NAME"* "/Volumes/$APP_NAME"*; do
  if [[ -d "$vol" ]]; then
    hdiutil detach "$vol" -force 2>/dev/null || true
    sleep 1
  fi
done

DMG_TEMP="$(mktemp -d /tmp/openclaw-dmg.XXXXXX)"
trap 'hdiutil detach "/Volumes/'"$DMG_VOLUME_NAME"'" -force 2>/dev/null || true; rm -rf "$DMG_TEMP" 2>/dev/null || true' EXIT

cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Copy LICENSE file to DMG
if [[ -f "$ROOT_DIR/LICENSE" ]]; then
  cp "$ROOT_DIR/LICENSE" "$DMG_TEMP/LICENSE.txt"
  echo "📄 Added LICENSE.txt to DMG"
fi

# Calculate required size with sufficient headroom.
# App bundles contain many small files; APFS overhead can be significant.
# Use 50% overhead or minimum 200MB extra, whichever is larger.
APP_SIZE_MB=$(du -sm "$APP_PATH" | awk '{print $1}')
OVERHEAD_MB=$((APP_SIZE_MB / 2))
if [[ "$OVERHEAD_MB" -lt 200 ]]; then
  OVERHEAD_MB=200
fi
DMG_SIZE_MB=$((APP_SIZE_MB + OVERHEAD_MB))
echo "App size: ${APP_SIZE_MB}MB, overhead: ${OVERHEAD_MB}MB, DMG size: ${DMG_SIZE_MB}MB"

DMG_RW_PATH="${OUT_PATH%.dmg}-rw.dmg"
rm -f "$DMG_RW_PATH" "$OUT_PATH"

hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_TEMP" \
  -ov \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "$DMG_RW_PATH"

MOUNT_POINT="/Volumes/$DMG_VOLUME_NAME"
if [[ -d "$MOUNT_POINT" ]]; then
  hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
  sleep 2
fi
hdiutil attach "$DMG_RW_PATH" -mountpoint "$MOUNT_POINT" -nobrowse

if [[ "${SKIP_DMG_STYLE:-0}" != "1" ]]; then
  mkdir -p "$MOUNT_POINT/.background"
  if [[ -f "$DMG_BACKGROUND_SMALL" ]]; then
    cp "$DMG_BACKGROUND_SMALL" "$MOUNT_POINT/.background/background.png"
  elif [[ -f "$DMG_BACKGROUND_PATH" ]]; then
    cp "$DMG_BACKGROUND_PATH" "$MOUNT_POINT/.background/background.png"
  else
    echo "WARN: DMG background missing: $DMG_BACKGROUND_SMALL / $DMG_BACKGROUND_PATH" >&2
  fi

  # Volume icon: reuse the app icon if available.
  ICON_SRC="$ROOT_DIR/apps/macos/Sources/OpenClaw/Resources/OpenClaw.icns"
  if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$MOUNT_POINT/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
    fi
  fi

  osascript <<EOF
tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$(to_applescript_list4 "$DMG_WINDOW_BOUNDS")}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to ${DMG_ICON_SIZE}
    if exists file ".background:background.png" then
      set background picture of viewOptions to file ".background:background.png"
    end if
    set text size of viewOptions to 12
    set label position of viewOptions to bottom
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to true
    set position of item "$APP_BUNDLE_NAME" of container window to {$(to_applescript_pair "$DMG_APP_POS")}
    set position of item "Applications" of container window to {$(to_applescript_pair "$DMG_APPS_POS")}
    if exists file "LICENSE.txt" then
      set position of item "LICENSE.txt" of container window to {$(to_applescript_pair "$DMG_LICENSE_POS")}
    end if
    update without registering applications
    delay 2
    close
    open
    delay 1
  end tell
end tell
EOF

  sleep 2
  osascript -e 'tell application "Finder" to close every window' || true
fi

for i in {1..5}; do
  if hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null; then
    break
  fi
  if [[ "$i" == "3" ]]; then
    hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
  fi
  sleep 2
done

hdiutil resize -limits "$DMG_RW_PATH" >/tmp/openclaw-dmg-limits.txt 2>/dev/null || true
MIN_SECTORS="$(tail -n 1 /tmp/openclaw-dmg-limits.txt 2>/dev/null | awk '{print $1}')"
rm -f /tmp/openclaw-dmg-limits.txt
if [[ "$MIN_SECTORS" =~ ^[0-9]+$ ]] && [[ "$DMG_EXTRA_SECTORS" =~ ^[0-9]+$ ]]; then
  TARGET_SECTORS=$((MIN_SECTORS + DMG_EXTRA_SECTORS))
  echo "Shrinking RW image: min sectors=$MIN_SECTORS (+$DMG_EXTRA_SECTORS) -> $TARGET_SECTORS"
  hdiutil resize -sectors "$TARGET_SECTORS" "$DMG_RW_PATH" >/dev/null 2>&1 || true
fi

hdiutil convert "$DMG_RW_PATH" -format ULMO -o "$OUT_PATH" -ov
rm -f "$DMG_RW_PATH"

hdiutil verify "$OUT_PATH" >/dev/null

# Calculate and display timing information
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
FINISH_TIME=$(date "+%Y-%m-%d %H:%M:%S")

echo "✅ DMG ready: $OUT_PATH"
echo "⏱  完成时间: $FINISH_TIME"
echo "⏱  DMG制作耗时: ${MINUTES}分${SECONDS}秒"
