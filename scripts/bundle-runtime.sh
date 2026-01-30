#!/usr/bin/env bash
set -euo pipefail

# Bundle Node.js runtime and OpenClaw CLI into the macOS app.
#
# Usage:
#   scripts/bundle-runtime.sh <app_resources_dir>
#
# Env:
#   NODE_VERSION     Node.js version to bundle (default: 22.13.1)
#   SKIP_NODE_DL     Skip Node.js download if already present (default: 0)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${1:-}"

if [[ -z "$RESOURCES_DIR" ]]; then
  echo "Usage: $0 <app_resources_dir>" >&2
  exit 1
fi

NODE_VERSION="${NODE_VERSION:-22.13.1}"
RUNTIME_DIR="$RESOURCES_DIR/runtime"
NODE_DIR="$RUNTIME_DIR/node"
CLI_DIR="$RUNTIME_DIR/openclaw"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  arm64)
    NODE_ARCH="arm64"
    ;;
  x86_64)
    NODE_ARCH="x64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

echo "📦 Bundling runtime for $ARCH (Node.js $NODE_VERSION)"

# Create directories
mkdir -p "$NODE_DIR"
mkdir -p "$CLI_DIR"

# Download Node.js if needed
NODE_TARBALL="node-v${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"
NODE_CACHE_DIR="$ROOT_DIR/.cache/node"
NODE_CACHE_FILE="$NODE_CACHE_DIR/$NODE_TARBALL"

if [[ "${SKIP_NODE_DL:-0}" != "1" ]] || [[ ! -f "$NODE_CACHE_FILE" ]]; then
  echo "⬇️  Downloading Node.js $NODE_VERSION for $NODE_ARCH..."
  mkdir -p "$NODE_CACHE_DIR"
  curl -fSL "$NODE_URL" -o "$NODE_CACHE_FILE"
fi

echo "📦 Extracting Node.js..."
# Extract only the node binary (not the entire tarball)
tar -xzf "$NODE_CACHE_FILE" -C "$NODE_DIR" --strip-components=2 "node-v${NODE_VERSION}-darwin-${NODE_ARCH}/bin/node"
chmod +x "$NODE_DIR/node"

# Verify node works
if ! "$NODE_DIR/node" --version >/dev/null 2>&1; then
  echo "ERROR: Bundled node binary doesn't work" >&2
  exit 1
fi
echo "✅ Node.js $(\"$NODE_DIR/node\" --version) bundled"

# Bundle OpenClaw CLI
echo "📦 Bundling OpenClaw CLI..."

# Copy built dist (only JS files, not macOS app artifacts)
if [[ ! -d "$ROOT_DIR/dist" ]]; then
  echo "ERROR: dist/ not found. Run 'pnpm build' first." >&2
  exit 1
fi

# Copy essential files - only copy JS/TS compiled output, not .app bundles
mkdir -p "$CLI_DIR/dist"
# Use rsync to exclude .app directories
rsync -a --exclude "*.app" --exclude "*.dmg" "$ROOT_DIR/dist/" "$CLI_DIR/dist/"
cp "$ROOT_DIR/package.json" "$CLI_DIR/"
cp "$ROOT_DIR/openclaw.mjs" "$CLI_DIR/"

# Copy node_modules from the project (already installed production deps)
echo "📦 Copying node_modules..."
if [[ -d "$ROOT_DIR/node_modules" ]]; then
  # Use rsync to copy only production dependencies efficiently
  # First, create a minimal package.json to know what deps we need
  "$NODE_DIR/node" -e "
const pkg = require('$ROOT_DIR/package.json');
const minimal = {
  name: pkg.name,
  version: pkg.version,
  type: pkg.type,
  main: pkg.main,
  dependencies: pkg.dependencies
};
console.log(JSON.stringify(minimal, null, 2));
" > "$CLI_DIR/package.json"

  # Copy node_modules
  cp -R "$ROOT_DIR/node_modules" "$CLI_DIR/"
else
  echo "ERROR: node_modules not found. Run 'pnpm install' first." >&2
  exit 1
fi

# Clean up unnecessary files to reduce size
echo "🧹 Cleaning up..."
# Remove dev-only and unnecessary files
find "$CLI_DIR/node_modules" -type f -name "*.md" -delete 2>/dev/null || true
find "$CLI_DIR/node_modules" -type f -name "*.ts" ! -name "*.d.ts" -delete 2>/dev/null || true
find "$CLI_DIR/node_modules" -type f -name "*.map" -delete 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name ".github" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "__tests__" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "example" -exec rm -rf {} + 2>/dev/null || true
find "$CLI_DIR/node_modules" -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

# Remove devDependencies packages that might have been hoisted
# This is a best-effort cleanup; the bundled CLI should still work
rm -rf "$CLI_DIR/node_modules/.pnpm" 2>/dev/null || true
rm -rf "$CLI_DIR/node_modules/.modules.yaml" 2>/dev/null || true

# Bundle extensions (plugins)
echo "📦 Bundling extensions..."
EXTENSIONS_DIR="$CLI_DIR/extensions"
mkdir -p "$EXTENSIONS_DIR"

# Copy only essential extensions (memory-core is required for default functionality)
# Add more extensions here as needed
BUNDLED_EXTENSIONS=(
  "memory-core"
)

for ext in "${BUNDLED_EXTENSIONS[@]}"; do
  if [[ -d "$ROOT_DIR/extensions/$ext" ]]; then
    echo "   📦 Bundling extension: $ext"
    cp -R "$ROOT_DIR/extensions/$ext" "$EXTENSIONS_DIR/"
  else
    echo "   ⚠️  Extension not found: $ext" >&2
  fi
done

# Bundle workspace templates (required for agent workspace bootstrap)
echo "📦 Bundling workspace templates..."
TEMPLATES_SRC="$ROOT_DIR/docs/reference/templates"
TEMPLATES_DEST="$CLI_DIR/docs/reference/templates"
if [[ -d "$TEMPLATES_SRC" ]]; then
  mkdir -p "$TEMPLATES_DEST"
  cp "$TEMPLATES_SRC"/*.md "$TEMPLATES_DEST/"
  TEMPLATE_COUNT=$(ls -1 "$TEMPLATES_DEST"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "   ✅ Copied $TEMPLATE_COUNT template files"
else
  echo "   ⚠️  Templates directory not found: $TEMPLATES_SRC" >&2
fi

# Calculate sizes
NODE_SIZE=$(du -sh "$NODE_DIR" | cut -f1)
CLI_SIZE=$(du -sh "$CLI_DIR" | cut -f1)
EXT_SIZE=$(du -sh "$EXTENSIONS_DIR" 2>/dev/null | cut -f1 || echo "0")
TOTAL_SIZE=$(du -sh "$RUNTIME_DIR" | cut -f1)

echo "✅ Runtime bundled:"
echo "   Node.js:    $NODE_SIZE"
echo "   CLI:        $CLI_SIZE"
echo "   Extensions: $EXT_SIZE"
echo "   Total:      $TOTAL_SIZE"
echo "   Path:       $RUNTIME_DIR"
