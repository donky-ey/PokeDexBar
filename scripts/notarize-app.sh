#!/bin/bash
# Produce the release ZIP only after Apple accepts the app and Gatekeeper allows it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/PokeDexBar.app"
ZIP="build/PokeDexBar.zip"
rm -f "$ZIP"
# Trust the Apple Developer ID chain and our team, not a self-signed certificate
# with the same display name. A valid seal alone does not imply Gatekeeper trust.
codesign --verify --deep --strict -R '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "K6AYHZNZZ2"' "$APP"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile PokeDexBar \
  --wait --output-format plist > "$WORK/result.plist"
STATUS=$(/usr/libexec/PlistBuddy -c 'Print :status' "$WORK/result.plist")
if [[ "$STATUS" != "Accepted" ]]; then
    cat "$WORK/result.plist" >&2
    echo "Notarization failed; no release ZIP was produced." >&2
    exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"
# The upload precedes stapling. Only this new archive contains the ticket.
ditto -c -k --keepParent "$APP" "$WORK/release.zip"
# Verify the actual archive after extraction, preserving its quarantine metadata.
ditto -x -k "$WORK/release.zip" "$WORK/extracted"
xcrun stapler validate "$WORK/extracted/PokeDexBar.app"
spctl --assess --type execute --verbose=4 "$WORK/extracted/PokeDexBar.app"
mv "$WORK/release.zip" "$ZIP"
echo "Verified notarized release: $ZIP"
