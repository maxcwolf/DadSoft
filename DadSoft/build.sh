#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building DadSoft..."
swift build -c release 2>&1

BINARY=".build/release/DadSoft"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed — binary not found."
    exit 1
fi

APP="DadSoft.app"
echo "Creating $APP bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Copy SPM resource bundles (images, etc.)
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && cp -r "$bundle" "$APP/Contents/Resources/"
done

# Strip extended attributes that break codesign
xattr -cr "$APP"

echo "Signing with entitlements..."
codesign --entitlements Resources/entitlements.plist \
         --force --deep -s - "$APP"

cp -r "$APP" ../
echo ""
echo "Done! Built: ../DadSoft.app"
echo "Double-click it to launch."
