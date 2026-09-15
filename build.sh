#!/bin/bash
# Builds "build/Peek Mail.app".
#
#   ./build.sh             build for this Mac (ad-hoc signed)
#   ./build.sh --install   build, then copy to /Applications
#
# Optional environment (used by the release workflow):
#   UNIVERSAL=1                 build for Apple Silicon and Intel
#   VERSION=1.2.3               sets CFBundleShortVersionString
#   BUILD_NUMBER=42             sets CFBundleVersion
#   CODESIGN_IDENTITY="Developer ID Application: …"
#                               sign with hardened runtime and secure timestamp
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP="build/Peek Mail.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

mkdir -p build
if [ "${UNIVERSAL:-0}" = "1" ]; then
    BINARIES=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx14.0"
        swift build -c release --product PeekMail --triple "$triple"
        BINARIES+=("$(swift build -c release --triple "$triple" --show-bin-path)/PeekMail")
    done
    lipo -create "${BINARIES[@]}" -output build/PeekMail
    BINARY=build/PeekMail
else
    swift build -c release --product PeekMail
    BINARY="$(swift build -c release --show-bin-path)/PeekMail"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/PeekMail"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

# Register with Launch Services so Finder offers the app for .eml/.msg files (skipped in CI).
if [ -z "${CI:-}" ]; then
    "$LSREGISTER" -f "$APP"
fi

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/Peek Mail.app"
    cp -R "$APP" /Applications/
    "$LSREGISTER" -f "/Applications/Peek Mail.app"
    echo "Installed to /Applications/Peek Mail.app"
else
    echo "Built $APP"
fi
