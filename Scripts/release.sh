#!/usr/bin/env bash
# Archive an unsigned .app, zip it, and print the SHA-256.
# v1 distribution is unsigned; the user adds Developer ID + notarization later.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f "José.xcodeproj/project.pbxproj" ]; then
    echo "Generating Xcode project..."
    ./Scripts/setup.sh
fi

VERSION=$(grep -A1 'MARKETING_VERSION' project.yml | head -1 | awk '{print $2}' | tr -d '"')
BUILD_DIR=".build/release"
ARCHIVE_PATH="$BUILD_DIR/José.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
ZIP_PATH="$BUILD_DIR/José-${VERSION}.zip"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"

echo "Archiving..."
xcodebuild \
    -project José.xcodeproj \
    -scheme José \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    archive

mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/José.app" "$EXPORT_PATH/"

# Re-sign ad-hoc with a stable, bundle-id-matching identifier.
# CODE_SIGNING_ALLOWED=NO above produces a "linker-signed" binary with
# Identifier=José (just the executable name) and an unbound Info.plist.
# macOS TCC keys permission grants by (bundle id, code signature) — with
# a wrong identifier and unbound Info.plist, the OS treats every launch
# as a fresh app, so Microphone / Accessibility grants don't stick and
# the user gets re-prompted forever. Re-signing with --identifier =
# bundle id, --options runtime, and the project's entitlements gives the
# bundle a coherent identity TCC will actually persist grants against.
echo "Re-signing ad-hoc with stable identifier..."
codesign --force --deep --sign - \
    --identifier com.ericyangchen.jose \
    --options runtime \
    --entitlements Resources/José.entitlements \
    "$EXPORT_PATH/José.app"

echo "Verifying..."
codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/José.app"

echo "Zipping..."
cd "$EXPORT_PATH"
ditto -c -k --keepParent "José.app" "../$(basename "$ZIP_PATH")"
cd - >/dev/null

SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo
echo "Built: $ZIP_PATH"
echo "SHA-256: $SHA"
