#!/usr/bin/env bash
set -euo pipefail

PROJECT="RightMenuMaster.xcodeproj"
SCHEME="RightMenuMaster"
TEAM_ID="${APPLE_TEAM_ID:-UC89362XVB}"
APP_ID="io.github.syjia06.rightclickmaster.dev"
EXTENSION_ID="io.github.syjia06.rightclickmaster.dev.finder"
APP_NAME="RightMenuMaster.app"
USER_CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR)"
DERIVED_DATA_PATH="${RCM_DERIVED_DATA_PATH:-${USER_CACHE_DIR}right-click-master/DerivedData}"
PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/Debug"
DEBUG_APP="$PRODUCTS_DIR/$APP_NAME"
INSTALL_APP="/Applications/RightClickMaster Dev.app"
INSTALL_EXT="$INSTALL_APP/Contents/PlugIns/FinderExtension.appex"

echo "Building clean Debug app..."
xcodegen generate
xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  clean build

if [[ ! -d "$DEBUG_APP" ]]; then
  echo "Build product not found: $DEBUG_APP" >&2
  exit 1
fi

echo "Removing stale Finder Sync registrations..."
while IFS= read -r plugin_path; do
  [[ -d "$plugin_path" ]] && pluginkit -r "$plugin_path" 2>/dev/null || true
done < <(
  pluginkit -m -A -D -v -i "$EXTENSION_ID" 2>/dev/null \
    | awk '/io\.github\.syjia06\.rightclickmaster\.dev\.finder/ { print $NF }'
)

killall RightMenuMaster 2>/dev/null || true
killall FinderExtension 2>/dev/null || true

echo "Installing to /Applications with ditto..."
rm -rf "$INSTALL_APP"
ditto "$DEBUG_APP" "$INSTALL_APP"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
codesign -dv "$INSTALL_APP" 2>&1 | grep -E "Identifier=$APP_ID|TeamIdentifier=" >/dev/null
codesign -dv "$INSTALL_EXT" 2>&1 | grep -E "Identifier=$EXTENSION_ID|TeamIdentifier=" >/dev/null

echo "Registering Finder Sync extension..."
pluginkit -a "$INSTALL_EXT"
pluginkit -e use -i "$EXTENSION_ID"

killall Finder
open "$INSTALL_APP"
sleep 2

echo "Current registration:"
pluginkit -m -A -D -v -i "$EXTENSION_ID"

echo "Current processes:"
pgrep -fl "RightMenuMaster|FinderExtension|Finder" || true
