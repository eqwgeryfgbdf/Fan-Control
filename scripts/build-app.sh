#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_MODE="${BUILD_MODE:-release}"
APP_VERSION="${APP_VERSION:-1.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo 'Invalid application version or build number.' >&2
  exit 1
fi
IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development:|Developer ID Application:/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
  echo 'A valid Apple Development or Developer ID identity is required for the authenticated control service.' >&2
  exit 1
fi
# Xcode 27.1's swiftbuild backend currently records SDK 15.0 when deployment is
# 15.0. Use the native backend so the real SDK is recorded and system Liquid Glass
# is enabled, while retaining a 15.0 minimum. Verify LC_BUILD_VERSION below.
swift build --build-system native -c "$BUILD_MODE" --triple arm64-apple-macosx15.0 --scratch-path .build/native-apple
BIN_PATH="$(swift build --build-system native -c "$BUILD_MODE" --triple arm64-apple-macosx15.0 --scratch-path .build/native-apple --show-bin-path)"
swift build --build-system native -c "$BUILD_MODE" --triple x86_64-apple-macosx15.0 --scratch-path .build/native-intel
INTEL_PATH="$(swift build --build-system native -c "$BUILD_MODE" --triple x86_64-apple-macosx15.0 --scratch-path .build/native-intel --show-bin-path)"
APP="$PWD/dist/Macmini contoral.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
lipo -create "$BIN_PATH/MacminiContoral" "$INTEL_PATH/MacminiContoral" -output "$APP/Contents/MacOS/MacminiContoral"
lipo -create "$BIN_PATH/MacminiHelper" "$INTEL_PATH/MacminiHelper" -output "$APP/Contents/MacOS/MacminiHelper"
cp Resources/local.macmini.contoral.helper.plist "$APP/Contents/Library/LaunchDaemons/"
codesign --force --options runtime --timestamp=none --identifier local.macmini.contoral.helper --sign "$IDENTITY" "$APP/Contents/MacOS/MacminiHelper"
TEAM="$(codesign -dv --verbose=4 "$APP/Contents/MacOS/MacminiHelper" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ ! "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then echo 'Missing signing team.' >&2; exit 1; fi
python3 - "$APP" "$TEAM" "$APP_VERSION" "$BUILD_NUMBER" <<'PY'
import sys, plistlib, pathlib
app, team, version, build = sys.argv[1:]
info = {
 'CFBundleExecutable':'MacminiContoral', 'CFBundleIdentifier':'local.macmini.contoral',
 'CFBundleName':'Macmini contoral', 'CFBundleDisplayName':'主機管理-Macmini contoral',
 'CFBundleDevelopmentRegion':'zh_TW', 'CFBundleLocalizations':['zh-Hant'],
 'CFBundlePackageType':'APPL','CFBundleShortVersionString':version,'CFBundleVersion':build,
 'LSMinimumSystemVersion':'15.0','NSHighResolutionCapable':True,
 'NSHumanReadableCopyright':'Copyright © 2026. See bundled third-party notices.',
 'MacminiSigningTeam':team, 'LSApplicationCategoryType':'public.app-category.utilities'
}
icon=pathlib.Path('Resources/AppIcon.icns')
if icon.exists():
 import shutil
 shutil.copy2(icon,pathlib.Path(app)/'Contents/Resources/AppIcon.icns')
 info['CFBundleIconFile']='AppIcon'
with open(pathlib.Path(app)/'Contents/Info.plist','wb') as f: plistlib.dump(info,f)
PY
if [[ -f THIRD_PARTY_NOTICES.md ]]; then cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"; fi
codesign --force --options runtime --timestamp=none --identifier local.macmini.contoral --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun vtool -show-build "$APP/Contents/MacOS/MacminiContoral"
echo "$APP"
