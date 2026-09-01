#!/bin/sh
set -eu

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.setforge.gymapp.ios}"
MARKETING_VERSION="${MARKETING_VERSION:-3.2.8}"
BUILD_NUMBER="${BUILD_NUMBER:-41}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/GymApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/build/AppStoreExport}"
DEFAULT_DERIVED_DATA_PATH="${TMPDIR:-/tmp/}GymApp-iOS-$MARKETING_VERSION-$BUILD_NUMBER-DerivedData"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$DEFAULT_DERIVED_DATA_PATH}"
EXPORT_OPTIONS="$ROOT/build/ExportOptions.plist"

mkdir -p "$ROOT/build" "$DERIVED_DATA_PATH"
DERIVED_DATA_PATH="$(CDPATH= cd -- "$DERIVED_DATA_PATH" && pwd -P)"
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
  -derivedDataPath "$DERIVED_DATA_PATH" \
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

IPA_PATH="$EXPORT_PATH/GymApp.ipa"
if [ ! -f "$IPA_PATH" ]; then
  echo "Export failed: GymApp.ipa was not created" >&2
  exit 1
fi

IPA_SCAN_DIR="$(mktemp -d "${TMPDIR:-/tmp/}GymApp-ipa-privacy.XXXXXX")"
cleanup_ipa_scan() {
  rm -rf "$IPA_SCAN_DIR"
}
trap cleanup_ipa_scan EXIT

unzip -tq "$IPA_PATH"
unzip -p "$IPA_PATH" > "$IPA_SCAN_DIR/payload.bin"
strings "$IPA_SCAN_DIR/payload.bin" > "$IPA_SCAN_DIR/strings.txt"
if LC_ALL=C grep -Eq '/Users/|/Volumes/|Documents/GymApp' "$IPA_SCAN_DIR/strings.txt"; then
  echo "Export blocked: the IPA contains a personal or workspace-local absolute path" >&2
  exit 1
fi

cleanup_ipa_scan
trap - EXIT

echo "Exported App Store package to $EXPORT_PATH"
