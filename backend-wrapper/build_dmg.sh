#!/bin/bash
# build_dmg.sh — builds TxemAI MLX Release, embeds oMLX Python bundle, creates DMG.
# Usage: ./backend-wrapper/build_dmg.sh
# Run from anywhere — script resolves paths automatically.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER_DIR="$REPO_ROOT/backend-wrapper"
OMLX_DIST="$REPO_ROOT/backend/packaging/dist/oMLX.app/Contents"
BUILD_DIR="/tmp/CortexML-build"
APP_SRC="$BUILD_DIR/Build/Products/Release/CortexML.app"
DIST_DIR="$WRAPPER_DIR/dist"
DMG_STAGING="$DIST_DIR/_staging"
DMG_OUT="$DIST_DIR/CortexML.dmg"

# ── Preflight ────────────────────────────────────────────────────────────────

echo "▶ Checking prerequisites…"

if [ ! -d "$OMLX_DIST" ]; then
    echo "✗ oMLX bundle not found at: $OMLX_DIST"
    echo "  Run: cd backend/packaging && python build.py"
    exit 1
fi

for required in \
    "$OMLX_DIST/Frameworks/cpython-3.11" \
    "$OMLX_DIST/Frameworks/framework-mlx-framework" \
    "$OMLX_DIST/Resources/omlx" \
    "$OMLX_DIST/MacOS/python3"; do
    if [ ! -e "$required" ]; then
        echo "✗ Missing: $required"
        exit 1
    fi
done

echo "  ✓ All prerequisites found."

# ── Step 1 — xcodebuild Release (no signing — we sign manually after embed) ──

echo ""
echo "▶ Step 1 — Building CortexML (Release)…"

xcodebuild \
    -project "$REPO_ROOT/CortexML.xcodeproj" \
    -scheme "CortexML" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | grep -E "^(▶|error:|warning:|BUILD |✓|✗)" || true

# Verify .app exists regardless of filtered output
if [ ! -d "$APP_SRC" ]; then
    # Re-run without filter to show actual error
    echo "✗ Build failed. Re-running to show errors:"
    xcodebuild \
        -project "$REPO_ROOT/CortexML.xcodeproj" \
        -scheme "CortexML" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build 2>&1 | tail -30
    exit 1
fi

echo "  ✓ Built: $APP_SRC"

# ── Step 2 — Embed Python layers ─────────────────────────────────────────────

echo ""
echo "▶ Step 2 — Embedding Python layers…"

mkdir -p \
    "$APP_SRC/Contents/Frameworks" \
    "$APP_SRC/Contents/Resources" \
    "$APP_SRC/Contents/MacOS"

echo "  cpython-3.11…"
rsync -a --delete --quiet \
    "$OMLX_DIST/Frameworks/cpython-3.11/" \
    "$APP_SRC/Contents/Frameworks/cpython-3.11/"

echo "  framework-mlx-framework…"
rsync -a --delete --quiet \
    "$OMLX_DIST/Frameworks/framework-mlx-framework/" \
    "$APP_SRC/Contents/Frameworks/framework-mlx-framework/"

echo "  omlx package…"
rsync -a --delete --quiet \
    "$OMLX_DIST/Resources/omlx/" \
    "$APP_SRC/Contents/Resources/omlx/"

echo "  python3 binary…"
cp -f "$OMLX_DIST/MacOS/python3" "$APP_SRC/Contents/MacOS/python3"
chmod +x "$APP_SRC/Contents/MacOS/python3"

if [ -d "$OMLX_DIST/lib" ]; then
    echo "  lib/…"
    mkdir -p "$APP_SRC/Contents/lib"
    rsync -a --delete --quiet \
        "$OMLX_DIST/lib/" \
        "$APP_SRC/Contents/lib/"
fi

echo "  start_server.sh…"
cp -f "$WRAPPER_DIR/start_server.sh" "$APP_SRC/Contents/Resources/start_server.sh"
chmod +x "$APP_SRC/Contents/Resources/start_server.sh"

echo "  ✓ Layers embedded."

# ── Step 3 — Ad-hoc sign ─────────────────────────────────────────────────────
# Shallow only — venvstacks uses dotted directory names that break --deep signing.

echo ""
echo "▶ Step 3 — Signing…"
codesign --force --sign - "$APP_SRC/Contents/MacOS/CortexML" 2>/dev/null || true
codesign --force --sign - "$APP_SRC" 2>/dev/null || true
echo "  ✓ Signed (ad-hoc, dev build)."

# ── Step 4 — Create DMG ───────────────────────────────────────────────────────

echo ""
echo "▶ Step 4 — Creating DMG…"

mkdir -p "$DIST_DIR"
rm -rf "$DMG_STAGING"
mkdir "$DMG_STAGING"

# Use ditto to copy — handles symlinks and resource forks correctly
ditto "$APP_SRC" "$DMG_STAGING/CortexML.app"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_OUT"

hdiutil create \
    -volname "CortexML" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -quiet \
    "$DMG_OUT"

rm -rf "$DMG_STAGING"

SIZE=$(du -sh "$DMG_OUT" | cut -f1)
echo "  ✓ DMG created: $DMG_OUT ($SIZE)"

echo ""
echo "✓ All done. Install:"
echo "  open \"$DMG_OUT\""
