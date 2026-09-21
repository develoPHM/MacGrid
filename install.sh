#!/bin/bash
# MacGrid 소스 빌드 + 설치 (오픈소스용). Xcode 필요.
# 사용: git clone <repo> && cd MacGrid && ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodebuild >/dev/null || { echo "Xcode가 필요합니다: App Store에서 Xcode 설치 후 다시 실행"; exit 1; }
xcodebuild -version >/dev/null 2>&1 || sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

echo "▶ 빌드 중 (1~2분)"
xcodebuild -project MacGrid.xcodeproj -scheme MacGrid -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" build -quiet

APP=build/Build/Products/Release/MacGrid.app
DEST=/Applications/MacGrid.app
[ -d "$APP" ] || { echo "빌드 실패"; exit 1; }

pkill -x MacGrid 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "✅ 설치 완료: $DEST  (⌃Space 또는 Dock/메뉴바 아이콘으로 실행)"
open "$DEST"
