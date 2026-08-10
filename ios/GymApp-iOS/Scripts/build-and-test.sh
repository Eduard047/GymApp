#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
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
