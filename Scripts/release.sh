#!/bin/zsh
#
# Builds, Developer-ID-signs, notarizes and staples DevScreenshot.app,
# then zips it for distribution (e.g. a GitHub Release).
#
# One-time prerequisites
# ----------------------
# 1. A "Developer ID Application" certificate in your keychain:
#      Xcode → Settings → Accounts → (your account) → Manage Certificates
#      → + → "Developer ID Application"
# 2. A notarytool keychain profile (stores your App Store Connect credentials):
#      xcrun notarytool store-credentials DevScreenshot-notary \
#        --apple-id "you@example.com" --team-id XF9U3N7W44 \
#        --password "xxxx-xxxx-xxxx-xxxx"      # an app-specific password
#
set -e
cd "$(dirname "$0")/.."

APP="DevScreenshot"
TEAM_ID="XF9U3N7W44"
NOTARY_PROFILE="DevScreenshot-notary"
BUILD="build"
ARCHIVE="$BUILD/$APP.xcarchive"
EXPORT="$BUILD/export"
APP_PATH="$EXPORT/$APP.app"
ZIP="$BUILD/$APP.zip"

rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "▸ Archiving (Release)…"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -archivePath "$ARCHIVE" archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet

echo "▸ Exporting with Developer ID…"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -exportPath "$EXPORT" -quiet

echo "▸ Notarizing (a few minutes)…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling ticket…"
xcrun stapler staple "$APP_PATH"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

echo "✓ Done → $ZIP"
echo "  Gatekeeper check: spctl -a -vvv -t install \"$APP_PATH\""
