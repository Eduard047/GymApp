#!/bin/sh
set -eu

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.setforge.gymapp.ios}"
MARKETING_VERSION="${MARKETING_VERSION:-2.2.9}"
BUILD_NUMBER="${BUILD_NUMBER:-17}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/GymApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/build/AppStoreExport}"
EXPORT_OPTIONS="$ROOT/build/ExportOptions.plist"

mkdir -p "$ROOT/build"
cp "$ROOT/AppStore/ExportOptions.plist" "$EXPORT_OPTIONS"
plutil -replace teamID -string "$DEVELOPMENT_TEAM" "$EXPORT_OPTIONS"

PROVISIONING_FLAG=""
if [ "${ALLOW_PROVISIONING_UPDATES:-0}" = "1" ]; then
  PROVISIONING_FLAG="-allowProvisioningUpdates"
fi

# shellcheck disable=SC2086
xcodebuild \
  -project "$ROOT/GymApp.xcodeproj" \
  -scheme GymApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  $PROVISIONING_FLAG \
  archive

# shellcheck disable=SC2086
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  $PROVISIONING_FLAG

echo "Exported App Store package to $EXPORT_PATH"
