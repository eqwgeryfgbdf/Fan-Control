#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/風扇管理 Fan Control.app"
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
ditto "$APP" "$STAGE/風扇管理 Fan Control.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安裝說明.txt" <<'NOTES'
風扇管理 Fan Control — 安裝與更新

1. 如有舊版，先恢復自動調節並結束 App。v1.0.2 已更名，請移除 Applications 中舊的 Macmini contoral.app，再安裝新版，避免保留兩份相同 App。
2. 將 風扇管理 Fan Control.app 拖到 Applications。
3. 從安裝位置開啟 App。更新舊版後，在設定按「重新啟動控制服務」。
4. 首次手動調速需在「系統設定 → 一般 → 登入項目與延伸功能」允許 風扇管理 Fan Control，並完成 macOS 要求的管理員驗證。

最低 macOS 15，Universal 包含 Apple Silicon 與 Intel。
本版已在 M4 Mac mini 測試手動調速及恢復自動；其他機型仍需實機驗證。
此為 Apple Development 簽署的開發版本，尚未經 Apple 公證。
NOTES
hdiutil create -volname "風扇管理 Fan Control $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"
