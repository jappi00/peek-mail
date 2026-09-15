#!/bin/bash
# Builds "build/Peek Mail.app". Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build -c release --product PeekMail
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Peek Mail.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PeekMail" "$APP/Contents/MacOS/PeekMail"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
# Register with Launch Services so Finder offers the app for .eml/.msg files.
"$LSREGISTER" -f "$APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/Peek Mail.app"
    cp -R "$APP" /Applications/
    "$LSREGISTER" -f "/Applications/Peek Mail.app"
    echo "Installed to /Applications/Peek Mail.app"
else
    echo "Built $APP"
fi
