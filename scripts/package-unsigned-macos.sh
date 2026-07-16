#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/RightMenuMaster.xcodeproj"
CACHE_NAMESPACE="$(getconf DARWIN_USER_CACHE_DIR)right-click-master"
BUILD_ROOT="$CACHE_NAMESPACE/unsigned-release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DMG_ROOT="$BUILD_ROOT/dmg-root"
ARTIFACT_DIR="$ROOT/.artifacts/macos"
APP_GROUP="io.github.syjia06.rightclickmaster.unsigned.shared"

cd "$ROOT"
xcodegen generate

rm -rf "$BUILD_ROOT"
mkdir -p "$DMG_ROOT" "$ARTIFACT_DIR"

xcodebuild -quiet \
  -project "$PROJECT" \
  -scheme RightMenuMaster \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM= \
  RCM_APP_GROUP="$APP_GROUP" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/RightMenuMaster.app"
APP="$DMG_ROOT/Right Click Master.app"
EXTENSION="$APP/Contents/PlugIns/FinderExtension.appex"
ditto "$BUILT_APP" "$APP"

MAIN_ENTITLEMENTS="$BUILD_ROOT/main.entitlements.plist"
EXTENSION_ENTITLEMENTS="$BUILD_ROOT/extension.entitlements.plist"
cp MainApp/RightMenuMaster.entitlements "$MAIN_ENTITLEMENTS"
cp FinderExtension/FinderExtension.entitlements "$EXTENSION_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP" "$MAIN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 $APP_GROUP" "$EXTENSION_ENTITLEMENTS"

codesign --force --sign - --options runtime --entitlements "$EXTENSION_ENTITLEMENTS" "$EXTENSION"
codesign --force --sign - --options runtime --entitlements "$MAIN_ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if find "$APP" \( -name '*.debug.dylib' -o -name '__preview.dylib' \) -print -quit | grep -q .; then
  echo "Unsigned release contains debug or preview dylibs" >&2
  exit 1
fi
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "Unsigned release contains get-task-allow" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ARTIFACT_DIR/RightMenuMaster-$VERSION-unsigned.dmg"
rm -f "$DMG" "$DMG.sha256"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Right Click Master" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG"
(
  cd "$ARTIFACT_DIR"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)

echo "Unsigned release ready: $DMG"
