#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Fan Control.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Invalid bundle version.' >&2
  exit 1
fi
DMG="$PWD/dist/Fan-Control-$VERSION-macos-universal.dmg"
if [[ -e "$DMG" || -e "$DMG.sha256" ]]; then
  echo "Refusing to replace an existing release artifact: $DMG" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
for binary in MacminiContoral MacminiHelper; do
  lipo "$APP/Contents/MacOS/$binary" -verify_arch arm64
  lipo "$APP/Contents/MacOS/$binary" -verify_arch x86_64
done
STAGE="$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Fan Control.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安裝說明.txt" <<'NOTES'
Fan Control — 安裝與更新

1. 如有舊版，先恢復自動調節並結束 App。新版名稱統一為 Fan Control；安裝後請移除舊的「風扇管理 Fan Control.app」或 Macmini contoral.app，避免保留兩份相同 App。
2. 將 Fan Control.app 拖到 Applications。
3. 從安裝位置開啟 App。更新舊版後，在設定按「重新啟動控制服務」。
4. 首次手動調速需在「系統設定 → 一般 → 登入項目與延伸功能」允許 Fan Control，並完成 macOS 要求的管理員驗證。

最低 macOS 15，Universal 包含 Apple Silicon 與 Intel。
v1.0.3 已在 M4 Mac mini 測試手動調速及恢復自動；新版與其他機型的實測範圍請參閱對應版本紀錄。
此為 Apple Development 簽署的開發版本，尚未經 Apple 公證。
NOTES
hdiutil create -volname "Fan Control $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"
