#!/usr/bin/env bash
# Convert a source image (PNG/JPG) to macOS .icns format
# Usage: ./create-icns.sh <source-image> <output.icns>

set -euo pipefail

SOURCE="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$SOURCE" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 <source-image> <output.icns>"
  echo "Example: $0 ~/my-icon.png ./AppIcon.icns"
  exit 1
fi

if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: Source image not found: $SOURCE"
  exit 1
fi

ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

echo "📐 Creating icon sizes..."
sips -z 16 16     "$SOURCE" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png"

echo "🖼  Converting to icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"

rm -rf "$(dirname "$ICONSET_DIR")"

echo "✅ Icon created: $OUTPUT"
