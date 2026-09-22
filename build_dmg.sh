#!/bin/bash
# Build a distributable DMG: Release build → disk image with "MacGrid.app + Applications shortcut".
# Usage: ./build_dmg.sh   → dist/MacGrid.dmg
# Note: the app is ad-hoc signed, so other Macs show a Gatekeeper warning (only Developer ID + notarization removes it).
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodebuild >/dev/null || { echo "Xcode is required."; exit 1; }

echo "▶ Release build"
xcodebuild -project MacGrid.xcodeproj -scheme MacGrid -configuration Release \
  -derivedDataPath build ARCHS=arm64 CODE_SIGN_IDENTITY="-" build -quiet

APP=build/Build/Products/Release/MacGrid.app
[ -d "$APP" ] || { echo "Build failed."; exit 1; }

echo "▶ Packaging DMG"
STAGE=build/dmg
rm -rf "$STAGE" dist; mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname MacGrid -srcfolder "$STAGE" -ov -format UDZO dist/MacGrid.dmg >/dev/null
rm -rf "$STAGE"
echo "✅ Done: dist/MacGrid.dmg"
