#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"

xcodebuild \
  -project "$ROOT/GymApp.xcodeproj" \
  -scheme GymApp \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  clean test
