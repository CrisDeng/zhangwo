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

# Build mode: universal (both architectures) or native (current machine only)
BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-1}"

# Pre-built node binary path (if exists, skip download)
PREBUILT_NODE="$ROOT_DIR/assets/node"

echo "📦 Bundling runtime (Node.js $NODE_VERSION)"

# Create directories
mkdir -p "$NODE_DIR"
mkdir -p "$CLI_DIR"

# Check for pre-built node binary first
if [[ -f "$PREBUILT_NODE" ]]; then
  echo "📦 Using pre-built Node.js from assets/node"
  cp "$PREBUILT_NODE" "$NODE_DIR/node"
  chmod +x "$NODE_DIR/node"
  echo "✅ Pre-built Node.js copied"
  file "$NODE_DIR/node"
else
  # Download and build node binary
  NODE_CACHE_DIR="$ROOT_DIR/.cache/node"
  mkdir -p "$NODE_CACHE_DIR"

  download_and_extract_node() {
    local arch="$1"
    local dest_dir="$2"
    local node_arch
    case "$arch" in
      arm64) node_arch="arm64" ;;
      x86_64) node_arch="x64" ;;
      *) echo "Unsupported architecture: $arch" >&2; return 1 ;;
    esac

    local tarball="node-v${NODE_VERSION}-darwin-${node_arch}.tar.gz"
    local url="https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"
    local cache_file="$NODE_CACHE_DIR/$tarball"

    if [[ "${SKIP_NODE_DL:-0}" != "1" ]] || [[ ! -f "$cache_file" ]]; then
      echo "⬇️  Downloading Node.js $NODE_VERSION for $node_arch..." >&2
      curl -fSL "$url" -o "$cache_file"
    fi

    rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    tar -xzf "$cache_file" -C "$dest_dir" --strip-components=2 "node-v${NODE_VERSION}-darwin-${node_arch}/bin/node"
  }

  if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
    echo "🔧 Building Universal Binary (arm64 + x86_64)..."

    NODE_ARM64_DIR="$NODE_CACHE_DIR/node-arm64"
    NODE_X64_DIR="$NODE_CACHE_DIR/node-x86_64"

    download_and_extract_node "arm64" "$NODE_ARM64_DIR"
    download_and_extract_node "x86_64" "$NODE_X64_DIR"

    echo "🔗 Creating Universal Binary with lipo..."
    lipo -create "$NODE_ARM64_DIR/node" "$NODE_X64_DIR/node" -output "$NODE_DIR/node"
    chmod +x "$NODE_DIR/node"

    # Clean up temp files
    rm -rf "$NODE_ARM64_DIR" "$NODE_X64_DIR"

    echo "✅ Universal Node.js bundled (arm64 + x86_64)"
    file "$NODE_DIR/node"
  else
    # Native build (current architecture only)
    ARCH="$(uname -m)"
    echo "🔧 Building for current architecture: $ARCH"

    NATIVE_NODE_DIR="$NODE_CACHE_DIR/node-$ARCH"
    download_and_extract_node "$ARCH" "$NATIVE_NODE_DIR"
    cp "$NATIVE_NODE_DIR/node" "$NODE_DIR/node"
    chmod +x "$NODE_DIR/node"
    rm -rf "$NATIVE_NODE_DIR"

    echo "✅ Node.js bundled for $ARCH"
  fi
fi

# Verify node works on current machine
NODE_VER=$("$NODE_DIR/node" --version 2>/dev/null || true)
if [[ -z "$NODE_VER" ]]; then
  echo "ERROR: Bundled node binary doesn't work" >&2
  exit 1
fi
echo "✅ Node.js $NODE_VER verified"

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
  "qqbot"
)

for ext in "${BUNDLED_EXTENSIONS[@]}"; do
  if [[ -d "$ROOT_DIR/extensions/$ext" ]]; then
    echo "   📦 Bundling extension: $ext"

    # Install dependencies if package.json exists and node_modules doesn't
    if [[ -f "$ROOT_DIR/extensions/$ext/package.json" ]] && [[ ! -d "$ROOT_DIR/extensions/$ext/node_modules" ]]; then
      echo "      📦 Installing dependencies for $ext..."
      (cd "$ROOT_DIR/extensions/$ext" && npm install --omit=dev 2>/dev/null) || true
    fi

    # Copy the extension (including node_modules)
    cp -R "$ROOT_DIR/extensions/$ext" "$EXTENSIONS_DIR/"

    # Remove .git directory if exists (don't bundle git history)
    rm -rf "$EXTENSIONS_DIR/$ext/.git" 2>/dev/null || true

    # Remove redundant/duplicate packages from extension node_modules
    # These are already included in the main CLI node_modules
    EXT_NODE_MODULES="$EXTENSIONS_DIR/$ext/node_modules"
    if [[ -d "$EXT_NODE_MODULES" ]]; then
      echo "      🧹 Cleaning redundant dependencies..."
      # Remove openclaw/clawdbot/moltbot (already in main CLI)
      rm -rf "$EXT_NODE_MODULES/openclaw" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/clawdbot" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/moltbot" 2>/dev/null || true
      # Remove typescript (not needed at runtime)
      rm -rf "$EXT_NODE_MODULES/typescript" 2>/dev/null || true
      # Remove dev-only and large packages that are already in main CLI
      rm -rf "$EXT_NODE_MODULES/pdfjs-dist" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/node-llama-cpp" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/@node-llama-cpp" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/playwright-core" 2>/dev/null || true
      rm -rf "$EXT_NODE_MODULES/chromium-bidi" 2>/dev/null || true
      # Remove test/docs/examples from remaining packages
      find "$EXT_NODE_MODULES" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
      find "$EXT_NODE_MODULES" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
      find "$EXT_NODE_MODULES" -type d -name "__tests__" -exec rm -rf {} + 2>/dev/null || true
      find "$EXT_NODE_MODULES" -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
      find "$EXT_NODE_MODULES" -type f -name "*.md" -delete 2>/dev/null || true
      find "$EXT_NODE_MODULES" -type f -name "*.map" -delete 2>/dev/null || true
    fi

    # Show size
    EXT_DEP_SIZE=$(du -sh "$EXTENSIONS_DIR/$ext" 2>/dev/null | cut -f1 || echo "?")
    echo "      ✅ $ext bundled ($EXT_DEP_SIZE)"
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
