#!/bin/zsh
#
# Build Release, sign with a STABLE identity, and install to /Applications.
#
# A stable signing identity matters: macOS ties Screen Recording / Accessibility
# permissions to the code signature. Ad-hoc signatures change on every build, so
# the granted permission is lost each time (symptom: black screenshots). Signing
# with a fixed Apple Development / Developer ID cert keeps the grant across rebuilds.
#
# Set DEVSCREENSHOT_SIGN_ID to a codesign identity (cert SHA-1 or name);
# defaults to ad-hoc "-" (which does NOT keep permissions stable).
#
set -e
cd "$(dirname "$0")/.."

APP="DevScreenshot"
SIGN_ID="${DEVSCREENSHOT_SIGN_ID:--}"

echo "▸ Building Release…"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -derivedDataPath build/dd build CODE_SIGN_IDENTITY="-" -quiet
BUILT="build/dd/Build/Products/Release/$APP.app"

echo "▸ Signing ($SIGN_ID)…"
codesign --force --options runtime --sign "$SIGN_ID" "$BUILT"

echo "▸ Installing to /Applications…"
pkill -x "$APP" 2>/dev/null || true
rm -rf "/Applications/$APP.app"
cp -R "$BUILT" /Applications/
open "/Applications/$APP.app"

echo "✓ /Applications/$APP.app  (signed: $SIGN_ID)"
