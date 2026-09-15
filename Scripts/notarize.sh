#!/bin/bash
# Notarizes an app bundle or DMG with Apple, then staples the ticket.
#
#   Scripts/notarize.sh "build/Peek Mail.app"
#   Scripts/notarize.sh build/PeekMail.dmg
#
# Requires an App Store Connect API key:
#   NOTARY_KEY_PATH   path to the .p8 file
#   NOTARY_KEY_ID     key ID
#   NOTARY_ISSUER_ID  issuer ID
set -euo pipefail

FILE="${1:?usage: notarize.sh <app-or-dmg>}"
: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is not set}"
: "${NOTARY_KEY_ID:?NOTARY_KEY_ID is not set}"
: "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is not set}"
AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

SUBMIT="$FILE"
if [ -d "$FILE" ]; then
    # App bundles are uploaded as a zip.
    SUBMIT="$(mktemp -d)/$(basename "$FILE" .app).zip"
    ditto -c -k --keepParent "$FILE" "$SUBMIT"
fi

echo "Submitting $(basename "$FILE") for notarization…"
RESULT=$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m --output-format json) || true
echo "$RESULT"

field() { /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))" <<<"$RESULT" 2>/dev/null || true; }
STATUS=$(field status)
SUBMISSION_ID=$(field id)

if [ "$STATUS" != "Accepted" ]; then
    echo "::error::Notarization of $(basename "$FILE") failed (status: ${STATUS:-unknown})"
    if [ -n "$SUBMISSION_ID" ]; then
        xcrun notarytool log "$SUBMISSION_ID" "${AUTH[@]}" || true
    fi
    exit 1
fi

xcrun stapler staple "$FILE"
echo "Notarized and stapled $(basename "$FILE")"
