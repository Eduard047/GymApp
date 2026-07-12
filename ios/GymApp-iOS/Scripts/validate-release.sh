#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ICON="$ROOT/GymApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

plutil -lint "$ROOT/GymApp/Resources/Info.plist"
plutil -lint "$ROOT/GymApp/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$ROOT/AppStore/ExportOptions.plist"

WIDTH="$(sips -g pixelWidth "$ICON" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$ICON" | awk '/pixelHeight/ {print $2}')"
ALPHA="$(sips -g hasAlpha "$ICON" | awk '/hasAlpha/ {print $2}')"
test "$WIDTH" = "1024"
test "$HEIGHT" = "1024"
test "$ALPHA" = "no"

if rg -n --hidden \
  -g '!build/**' \
  -g '!AppStore/APP_STORE_CHECKLIST.md' \
  -e 'service_role' \
  -e 'SUPABASE_SERVICE_ROLE_KEY\s*=' \
  -e 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' \
  "$ROOT/GymApp"; then
  echo "Potential privileged credential found in the app target." >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT/GymApp.xcodeproj" \
  -scheme GymApp \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$ROOT/build/ReleaseValidation" \
  CODE_SIGNING_ALLOWED=NO \
  build
