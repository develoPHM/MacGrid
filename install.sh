#!/bin/bash
# Build MacGrid from source and install it. Requires: Apple Silicon, macOS 26 (Tahoe) or later, Xcode.
# Usage: git clone <repo> && cd MacGrid && ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

[ "$(uname -m)" = "arm64" ] || { echo "MacGrid requires an Apple Silicon Mac."; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] || { echo "MacGrid requires macOS 26 (Tahoe) or later."; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode is required. Install it from the App Store and run again."; exit 1; }
xcodebuild -version >/dev/null 2>&1 || sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

echo "▶ Building (1–2 min)"
xcodebuild -project MacGrid.xcodeproj -scheme MacGrid -configuration Release \
  -derivedDataPath build ARCHS=arm64 CODE_SIGN_IDENTITY="-" build -quiet

APP=build/Build/Products/Release/MacGrid.app
DEST=/Applications/MacGrid.app
[ -d "$APP" ] || { echo "Build failed."; exit 1; }

pkill -x MacGrid 2>/dev/null || true
while pgrep -xq MacGrid; do sleep 0.2; done   # wait for the old instance to exit (opening too early gives error -600)
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "✅ Installed: $DEST  (open with ⌃Space, the Dock icon or the menu bar icon)"
sleep 1
open "$DEST"
