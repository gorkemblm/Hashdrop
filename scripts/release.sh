#!/usr/bin/env bash
# Builds, signs, notarizes and staples build/Hashdrop-<version>.dmg, ready for a GitHub release.
#
# One-time setup (needs a paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate:
#      Xcode → Settings → Accounts → (your team) → Manage Certificates… → + → Developer ID Application
#   2. Store notarization credentials in the keychain, either with an App Store Connect API key
#      (Users and Access → Integrations → Team Keys, "Developer" access; the .p8 can be deleted afterwards):
#      xcrun notarytool store-credentials hashdrop-notary --key AuthKey_XXXX.p8 --key-id <KEYID> --issuer <ISSUER-ID>
#      or with an app-specific password from appleid.apple.com:
#      xcrun notarytool store-credentials hashdrop-notary --apple-id <you@example.com> --team-id <TEAMID>
#
# Usage: VERSION=1.0.0 ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, e.g. VERSION=1.0.0 ./scripts/release.sh}"
PROFILE="${NOTARY_PROFILE:-hashdrop-notary}"

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [[ -z "$IDENTITY" ]]; then
  echo "No 'Developer ID Application' certificate found — see the setup notes at the top of this script." >&2
  exit 1
fi

VERSION="$VERSION" SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh

DMG="build/Hashdrop-$VERSION.dmg"
STAGING="$(mktemp -d)"
cp -R build/Hashdrop.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Hashdrop" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "Notarizing (usually a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# Also keep a version-less copy so .../releases/latest/download/Hashdrop.dmg always serves the newest build.
cp "$DMG" build/Hashdrop.dmg

shasum -a 256 "$DMG"
echo "Ready: $DMG (+ build/Hashdrop.dmg) — attach build/Hashdrop.dmg to the GitHub release for v$VERSION."
