#!/bin/bash
# Writes build/appcast.xml for Sparkle with a single item for this release.
#
#   Scripts/make-appcast.sh <version> <build-number> <signature> <release-notes.html>
#
# The DMG is expected at build/PeekMail.dmg and is downloaded from the GitHub release for tag v<version>.
# <signature> is the EdDSA signature printed by Sparkle's `sign_update -p`.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version}"
BUILD_NUMBER="${2:?build number}"
SIGNATURE="${3:?EdDSA signature}"
NOTES_FILE="${4:?release notes HTML file}"

DMG="build/PeekMail.dmg"
LENGTH=$(stat -f%z "$DMG")
DOWNLOAD_URL="https://github.com/jappi00/peek-mail/releases/download/v$VERSION/PeekMail.dmg"
RELEASE_URL="https://github.com/jappi00/peek-mail/releases/tag/v$VERSION"
MINIMUM_SYSTEM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)
# Sparkle expects three components, e.g. 14.0.0.
while [ "$(echo "$MINIMUM_SYSTEM" | tr -cd '.' | wc -c | tr -d ' ')" -lt 2 ]; do MINIMUM_SYSTEM="$MINIMUM_SYSTEM.0"; done
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
# CDATA can't contain "]]>"; split it if release notes ever do.
NOTES=$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES_FILE")

cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Peek Mail</title>
    <link>https://peekmail.oesterl.ing/</link>
    <description>Updates for Peek Mail</description>
    <language>en</language>
    <item>
      <title>Peek Mail $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$RELEASE_URL</sparkle:fullReleaseNotesLink>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="$DOWNLOAD_URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE" />
    </item>
  </channel>
</rss>
EOF

echo "Wrote build/appcast.xml (Peek Mail $VERSION, build $BUILD_NUMBER, $LENGTH bytes)"
