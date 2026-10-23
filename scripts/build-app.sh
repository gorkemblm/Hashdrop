#!/usr/bin/env bash
# Builds build/Hashdrop.app (universal: Apple Silicon + Intel).
#
#   VERSION=1.2.0        marketing version (default: latest git tag, else 0.1.0)
#   SIGN_IDENTITY=...    codesign identity. Default: the first "Developer ID Application" identity,
#                        else "Apple Development" (keeps Accessibility permission across local rebuilds),
#                        else ad-hoc ("-").
#   ARCHS="arm64"        build a single architecture (faster for local iteration)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Hashdrop"
BUNDLE_ID="${BUNDLE_ID:-io.github.gorkemblm.hashdrop}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS="${ARCHS:-arm64 x86_64}"

find_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep "$1" | head -1 | sed -E 's/.*"(.*)"/\1/' || true
}
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(find_identity "Developer ID Application")"
  [[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY="$(find_identity "Apple Development")"
  [[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY="-"
fi

arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done
swift build -c release "${arch_flags[@]}"
BIN="$(swift build -c release "${arch_flags[@]}" --show-bin-path)/Hashdrop"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hashdrop"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Hashdrop</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Gorkem Bilim. MIT License.</string>
</dict>
</plist>
PLIST

sign_flags=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  # Hardened runtime + secure timestamp are required for notarization.
  sign_flags+=(--options runtime --timestamp)
fi
codesign "${sign_flags[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Hashdrop"), signed: $SIGN_IDENTITY)"
