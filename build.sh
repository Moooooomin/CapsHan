#!/bin/bash
# Builds CapsHan.app (Apple Silicon + Intel) and a DMG for distribution.
#
#   ./build.sh                                   # ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" ./build.sh   # signed for notarization
#
# Options (environment variables): BUNDLE_ID, VERSION, BUILD_NUMBER, SIGN_IDENTITY
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CapsHan"
BUNDLE_ID="${BUNDLE_ID:-io.github.moooooomin.capshan}"
VERSION="${VERSION:-1.4.0}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
MIN_MACOS="13.0"

BUILD_DIR="build"
DIST_DIR="dist"
APP="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST_DIR"

echo "==> Compiling"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 \
        -target "$arch-apple-macos$MIN_MACOS" \
        Sources/*.swift \
        -o "$BUILD_DIR/$APP_NAME-$arch"
done
lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"

echo "==> Bundling"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "==> Packaging DMG"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "Done: $APP"
echo "      $DMG"
