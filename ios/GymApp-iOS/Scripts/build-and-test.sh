#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if [ -z "${DESTINATION:-}" ]; then
  # Use the first available iPhone simulator instead of a fixed model whose
  # runtime may not be installed on this Mac.
  DEVICE_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  if [ -z "$DEVICE_ID" ]; then
    echo "No available iPhone simulator. Set DESTINATION explicitly." >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi
CREATED_DERIVED_DATA=""

cleanup() {
  if [ -n "$CREATED_DERIVED_DATA" ] && [ "$DERIVED_DATA" = "$CREATED_DERIVED_DATA" ]; then
    rm -rf -- "$CREATED_DERIVED_DATA"
  fi
}

if [ -z "${DERIVED_DATA:-}" ]; then
  TEMP_ROOT="${TMPDIR:-/private/tmp}"
  DERIVED_DATA="$(mktemp -d "$TEMP_ROOT/gymapp-ios-derived-data.XXXXXX")"
  CREATED_DERIVED_DATA="$DERIVED_DATA"
  trap cleanup EXIT
fi

xcodebuild \
  -project "$ROOT/GymApp.xcodeproj" \
  -scheme GymApp \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  clean test
