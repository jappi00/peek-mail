#!/bin/bash
# Builds "build/Peek Mail.app".
#
#   ./build.sh             build for this Mac (ad-hoc signed)
#   ./build.sh --install   build, then copy to /Applications
#
# Optional environment (used by the release workflow):
#   UNIVERSAL=1                 build for Apple Silicon and Intel
#   VERSION=1.2.3               sets CFBundleShortVersionString
#   BUILD_NUMBER=42             sets CFBundleVersion (Sparkle compares this, so it must increase)
#   CODESIGN_IDENTITY="Developer ID Application: …"
#                               sign with hardened runtime and secure timestamp
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP="build/Peek Mail.app"
IDENTITY="${CODESIGN_IDENTITY:--}"
# Universal (arm64 + x86_64) Sparkle framework from the resolved Swift package.
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

mkdir -p build
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    ARCH_FLAGS=()
fi
swift build -c release --product PeekMail ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BINARY="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/PeekMail"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS=" $(lipo -archs "$BINARY") "
    if [[ "$ARCHS" != *" arm64 "* || "$ARCHS" != *" x86_64 "* ]]; then
        echo "error: $BINARY is not universal (architectures:$ARCHS)" >&2
        exit 1
    fi
fi
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "error: $SPARKLE_FRAMEWORK not found (run 'swift package resolve')" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/PeekMail"
# The app loads Sparkle from Contents/Frameworks.
if ! otool -l "$APP/Contents/MacOS/PeekMail" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PeekMail"
fi
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
# Peek Mail isn't sandboxed, so Sparkle's XPC services aren't needed.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

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

# Sign inside-out, as documented by Sparkle (never with --deep).
if [ "$IDENTITY" = "-" ]; then
    SIGN=(codesign --force --sign -)
else
    SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

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
