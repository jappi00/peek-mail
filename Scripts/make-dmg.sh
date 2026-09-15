#!/bin/bash
# Packages "build/Peek Mail.app" into build/PeekMail.dmg with an Applications shortcut.
# Signs the DMG when CODESIGN_IDENTITY is set to a real identity (not "-").
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Peek Mail.app"
DMG="build/PeekMail.dmg"
STAGING="build/dmg-staging"

[ -d "$APP" ] || { echo "error: $APP not found, run ./build.sh first" >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Peek Mail.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Peek Mail" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

echo "Created $DMG"
