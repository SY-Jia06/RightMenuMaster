#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to the Apple Developer Team ID}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool keychain profile}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/RightMenuMaster.xcodeproj"
SCHEME="RightMenuMaster"
USER_CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR)"
CACHE_NAMESPACE="${USER_CACHE_DIR}right-click-master"
BUILD_ROOT="${RCM_BUILD_ROOT:-$CACHE_NAMESPACE/release}"
ARCHIVE="$BUILD_ROOT/RightMenuMaster.xcarchive"
EXPORT_DIR="$BUILD_ROOT/export"
DMG_ROOT="$BUILD_ROOT/dmg-root"
ARTIFACT_DIR="$ROOT/.artifacts/macos"
EXPORT_OPTIONS="$ROOT/scripts/ExportOptions-DeveloperID.plist"
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi

# This script performs a clean release build. Keep its recursive deletion
# strictly inside the dedicated per-user cache namespace, even when an
# override is supplied by CI or a developer.
case "$BUILD_ROOT" in
  "$CACHE_NAMESPACE"/*)
    BUILD_LEAF="${BUILD_ROOT#"$CACHE_NAMESPACE"/}"
    ;;
  *)
    echo "RCM_BUILD_ROOT must stay inside $CACHE_NAMESPACE" >&2
    exit 1
    ;;
esac
case "$BUILD_LEAF" in
  "" | "." | ".." | */*)
    echo "RCM_BUILD_ROOT must be one direct child of the dedicated cache namespace" >&2
    exit 1
    ;;
esac
mkdir -p "$CACHE_NAMESPACE"
CACHE_NAMESPACE_REAL="$(cd "$CACHE_NAMESPACE" && pwd -P)"
BUILD_ROOT="$CACHE_NAMESPACE_REAL/$BUILD_LEAF"
ARCHIVE="$BUILD_ROOT/RightMenuMaster.xcarchive"
EXPORT_DIR="$BUILD_ROOT/export"
DMG_ROOT="$BUILD_ROOT/dmg-root"

security_entitlement_keys() {
  local entitlements="$1"
  plutil -convert xml1 -o - "$entitlements" |
    sed -n 's|^[[:space:]]*<key>\(com\.apple\.security\.[^<]*\)</key>[[:space:]]*$|\1|p' |
    LC_ALL=C sort
}

audit_forbidden_binary_strings() {
  local binary="$1"
  local matches
  matches="$(strings -a "$binary" | grep -E \
    'trash-file|AppCommandURL|PendingFileCreationStore|FinderMonitorDirectories|NSAppleScript|Library/Mobile Documents' || true)"
  if [[ -n "$matches" ]]; then
    echo "Legacy or high-risk implementation markers found in release binary: $binary" >&2
    printf '%s\n' "$matches" >&2
    exit 1
  fi
}

submit_notarization() {
  local artifact="$1"
  local label="$2"
  local submit_json="$ARTIFACT_DIR/notary-$label-submit.json"
  local log_json="$ARTIFACT_DIR/notary-$label-log.json"
  local submission_id
  local status
  local command_status=0

  rm -f "$submit_json" "$log_json"
  xcrun notarytool submit \
    "${NOTARY_ARGS[@]}" \
    --wait \
    --output-format json \
    "$artifact" > "$submit_json" || command_status=$?

  if ! plutil -lint "$submit_json" >/dev/null; then
    echo "Notarization did not return valid JSON: $artifact" >&2
    exit 1
  fi

  if ! submission_id="$(plutil -extract id raw -o - "$submit_json")" || \
    ! status="$(plutil -extract status raw -o - "$submit_json")"; then
    echo "Notarization result is missing id or status: $artifact" >&2
    exit 1
  fi
  if ! xcrun notarytool log \
    "${NOTARY_ARGS[@]}" \
    "$submission_id" \
    "$log_json"; then
    echo "Unable to retrieve notarization log: artifact=$artifact id=$submission_id" >&2
    exit 1
  fi
  if ! plutil -lint "$log_json" >/dev/null; then
    echo "Notarization log is not valid JSON: artifact=$artifact id=$submission_id" >&2
    exit 1
  fi

  if [[ "$command_status" -ne 0 || "$status" != "Accepted" ]]; then
    echo "Notarization was not accepted: artifact=$artifact status=$status command_status=$command_status" >&2
    exit 1
  fi
}

cd "$ROOT"
xcodegen generate

rm -rf "$BUILD_ROOT"
mkdir -p "$EXPORT_DIR" "$DMG_ROOT" "$ARTIFACT_DIR"

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

APP="$EXPORT_DIR/RightMenuMaster.app"
if [[ ! -d "$APP" ]]; then
  echo "Release app missing: $APP" >&2
  exit 1
fi

if find "$APP" \( -name '*.debug.dylib' -o -name '__preview.dylib' \) -print -quit | grep -q .; then
  echo "Release app contains debug or preview dylibs" >&2
  exit 1
fi

SIGNING_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
grep -q 'Authority=Developer ID Application:' <<<"$SIGNING_DETAILS" || {
  echo "Release app is not signed with Developer ID Application" >&2
  exit 1
}
grep -q 'runtime' <<<"$SIGNING_DETAILS" || {
  echo "Release app does not enable Hardened Runtime" >&2
  exit 1
}
grep -q 'Timestamp=' <<<"$SIGNING_DETAILS" || {
  echo "Release app does not contain a secure signing timestamp" >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP"

EXTENSION="$APP/Contents/PlugIns/FinderExtension.appex"
if [[ ! -d "$EXTENSION" ]]; then
  echo "Finder extension missing: $EXTENSION" >&2
  exit 1
fi

audit_forbidden_binary_strings "$APP/Contents/MacOS/RightMenuMaster"
audit_forbidden_binary_strings "$EXTENSION/Contents/MacOS/FinderExtension"

EXTENSION_SIGNING_DETAILS="$(codesign -dv --verbose=4 "$EXTENSION" 2>&1)"
grep -q 'Authority=Developer ID Application:' <<<"$EXTENSION_SIGNING_DETAILS" || {
  echo "Finder extension is not signed with Developer ID Application" >&2
  exit 1
}
grep -q 'runtime' <<<"$EXTENSION_SIGNING_DETAILS" || {
  echo "Finder extension does not enable Hardened Runtime" >&2
  exit 1
}
grep -q 'Timestamp=' <<<"$EXTENSION_SIGNING_DETAILS" || {
  echo "Finder extension does not contain a secure signing timestamp" >&2
  exit 1
}

MAIN_TEAM="$(sed -n 's/^TeamIdentifier=//p' <<<"$SIGNING_DETAILS" | head -n 1)"
EXTENSION_TEAM="$(sed -n 's/^TeamIdentifier=//p' <<<"$EXTENSION_SIGNING_DETAILS" | head -n 1)"
if [[ "$MAIN_TEAM" != "$APPLE_TEAM_ID" || "$EXTENSION_TEAM" != "$APPLE_TEAM_ID" ]]; then
  echo "Signing TeamIdentifier mismatch: expected=$APPLE_TEAM_ID app=$MAIN_TEAM extension=$EXTENSION_TEAM" >&2
  exit 1
fi

MAIN_ENTITLEMENTS="$BUILD_ROOT/main.entitlements.plist"
EXTENSION_ENTITLEMENTS="$BUILD_ROOT/extension.entitlements.plist"
codesign -d --xml --entitlements - "$APP" > "$MAIN_ENTITLEMENTS"
codesign -d --xml --entitlements - "$EXTENSION" > "$EXTENSION_ENTITLEMENTS"

for entitlements in "$MAIN_ENTITLEMENTS" "$EXTENSION_ENTITLEMENTS"; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements")" == "true" ]] || {
    echo "App Sandbox is missing: $entitlements" >&2
    exit 1
  }
  if grep -q 'temporary-exception' "$entitlements"; then
    echo "Temporary exception entitlement found: $entitlements" >&2
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null | grep -q true; then
    echo "Release artifact contains get-task-allow: $entitlements" >&2
    exit 1
  fi
done

EXPECTED_MAIN_SECURITY_KEYS="$(printf '%s\n' \
  'com.apple.security.app-sandbox' \
  'com.apple.security.application-groups' \
  'com.apple.security.files.bookmarks.app-scope' \
  'com.apple.security.files.user-selected.read-write' | LC_ALL=C sort)"
EXPECTED_EXTENSION_SECURITY_KEYS="$(printf '%s\n' \
  'com.apple.security.app-sandbox' \
  'com.apple.security.application-groups' | LC_ALL=C sort)"
ACTUAL_MAIN_SECURITY_KEYS="$(security_entitlement_keys "$MAIN_ENTITLEMENTS")"
ACTUAL_EXTENSION_SECURITY_KEYS="$(security_entitlement_keys "$EXTENSION_ENTITLEMENTS")"

if [[ "$ACTUAL_MAIN_SECURITY_KEYS" != "$EXPECTED_MAIN_SECURITY_KEYS" ]]; then
  echo "Main app security entitlement allowlist mismatch" >&2
  diff -u \
    <(printf '%s\n' "$EXPECTED_MAIN_SECURITY_KEYS") \
    <(printf '%s\n' "$ACTUAL_MAIN_SECURITY_KEYS") >&2 || true
  exit 1
fi
if [[ "$ACTUAL_EXTENSION_SECURITY_KEYS" != "$EXPECTED_EXTENSION_SECURITY_KEYS" ]]; then
  echo "Finder extension security entitlement allowlist mismatch" >&2
  diff -u \
    <(printf '%s\n' "$EXPECTED_EXTENSION_SECURITY_KEYS") \
    <(printf '%s\n' "$ACTUAL_EXTENSION_SECURITY_KEYS") >&2 || true
  exit 1
fi

MAIN_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$MAIN_ENTITLEMENTS")"
EXTENSION_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$EXTENSION_ENTITLEMENTS")"
if [[ "$MAIN_GROUP" != "$APPLE_TEAM_ID."* || "$MAIN_GROUP" != "$EXTENSION_GROUP" ]]; then
  echo "App Group mismatch or wrong team: app=$MAIN_GROUP extension=$EXTENSION_GROUP" >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:1' "$MAIN_ENTITLEMENTS" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:1' "$EXTENSION_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "Release targets must contain exactly one App Group" >&2
  exit 1
fi

MAIN_INFO="$APP/Contents/Info.plist"
EXTENSION_INFO="$EXTENSION/Contents/Info.plist"
MAIN_INFO_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :RCMAppGroup' "$MAIN_INFO")"
EXTENSION_INFO_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :RCMAppGroup' "$EXTENSION_INFO")"
EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$EXTENSION_INFO")"
if [[ "$MAIN_INFO_GROUP" != "$MAIN_GROUP" || "$EXTENSION_INFO_GROUP" != "$MAIN_GROUP" ]]; then
  echo "Info.plist RCMAppGroup does not match signed entitlement: app=$MAIN_INFO_GROUP extension=$EXTENSION_INFO_GROUP signed=$MAIN_GROUP" >&2
  exit 1
fi
if [[ "$EXTENSION_POINT" != "com.apple.FinderSync" ]]; then
  echo "Unexpected Finder extension point: $EXTENSION_POINT" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  EXPECTED_TAG="v$VERSION"
  if [[ "${GITHUB_REF_NAME:-}" != "$EXPECTED_TAG" ]]; then
    echo "Release tag/version mismatch: tag=${GITHUB_REF_NAME:-missing} expected=$EXPECTED_TAG" >&2
    exit 1
  fi
fi

ZIP="$BUILD_ROOT/RightMenuMaster-notarization.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
submit_notarization "$ZIP" "app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

SPCTL_APP="$(spctl --assess --type execute --verbose=4 "$APP" 2>&1 || true)"
if grep -qi 'security disabled' <<<"$SPCTL_APP"; then
  echo "$SPCTL_APP" >&2
  echo "Gatekeeper is disabled; acceptance result is not valid release evidence" >&2
  exit 1
fi
grep -q 'accepted' <<<"$SPCTL_APP" || {
  echo "$SPCTL_APP" >&2
  echo "Gatekeeper did not report the app as accepted" >&2
  exit 1
}

DMG="$ARTIFACT_DIR/RightMenuMaster-$VERSION.dmg"
rm -f "$DMG" "$DMG.sha256"

DMG_APP="$DMG_ROOT/Right Click Master.app"
ditto "$APP" "$DMG_APP"
codesign --verify --deep --strict --verbose=2 "$DMG_APP"
xcrun stapler validate "$DMG_APP"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Right Click Master" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG"

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"
DMG_SIGNING_DETAILS="$(codesign -dv --verbose=4 "$DMG" 2>&1)"
grep -q 'Authority=Developer ID Application:' <<<"$DMG_SIGNING_DETAILS" || {
  echo "DMG is not signed with Developer ID Application" >&2
  exit 1
}
grep -q 'Timestamp=' <<<"$DMG_SIGNING_DETAILS" || {
  echo "DMG does not contain a secure signing timestamp" >&2
  exit 1
}
DMG_TEAM="$(sed -n 's/^TeamIdentifier=//p' <<<"$DMG_SIGNING_DETAILS" | head -n 1)"
if [[ "$DMG_TEAM" != "$APPLE_TEAM_ID" ]]; then
  echo "DMG signing TeamIdentifier mismatch: expected=$APPLE_TEAM_ID actual=$DMG_TEAM" >&2
  exit 1
fi

submit_notarization "$DMG" "dmg"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --verbose=2 "$DMG"

SPCTL_DMG="$(spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 || true)"
if grep -qi 'security disabled' <<<"$SPCTL_DMG"; then
  echo "$SPCTL_DMG" >&2
  echo "Gatekeeper is disabled; DMG acceptance result is not valid release evidence" >&2
  exit 1
fi
grep -q 'accepted' <<<"$SPCTL_DMG" || {
  echo "$SPCTL_DMG" >&2
  echo "Gatekeeper did not report the DMG as accepted" >&2
  exit 1
}

(
  cd "$ARTIFACT_DIR"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)
echo "Release ready: $DMG"
