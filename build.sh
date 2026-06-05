#!/bin/zsh
#
# Builds DevScreenshot.app (menu-bar app) from source — no Xcode project needed.
#
set -e
cd "$(dirname "$0")"

APP="DevScreenshot.app"
BIN="DevScreenshot"
BUNDLE_ID="de.rippcon.devscreenshot"

echo "▸ Generating icon…"
swift make-icon.swift AppIcon.png

ICONSET="$(mktemp -d)/DevScreenshot.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz             AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
    sips -z $((sz*2)) $((sz*2)) AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done

echo "▸ Compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -O main.swift -o "$APP/Contents/MacOS/$BIN" \
    -framework Cocoa -framework ApplicationServices -framework ServiceManagement

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DevScreenshot</string>
    <key>CFBundleDisplayName</key><string>DevScreenshot</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Accessibility / Screen-Recording grants survive relaunches.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ Built $(pwd)/$APP"
