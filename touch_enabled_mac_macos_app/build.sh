#!/bin/bash
# Builds TE Keyboard.app and packages it into a DMG in dist/
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
IDENTIFIER="com.rishav.touchenabledmac"
APP="build/Touch Enabled Mac.app"
VOL="Touch Enabled Mac"
DMG="dist/Touch Enabled Mac-$VERSION.dmg"
PKG="dist/Touch Enabled Mac-$VERSION.pkg"

rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

echo "• compiling (arm64 + x86_64)…"
swiftc -O main.swift -o "build/te-arm64" -target arm64-apple-macosx12.0
swiftc -O main.swift -o "build/te-x64" -target x86_64-apple-macosx12.0
lipo -create "build/te-arm64" "build/te-x64" -output "$APP/Contents/MacOS/Touch Enabled Mac"
rm "build/te-arm64" "build/te-x64"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f AppIcon.icns ]; then cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

echo "• signing (ad-hoc)…"
codesign --force --deep -s - "$APP"

echo "• building DMG…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"

echo "• building PKG installer…"
pkgbuild --component "$APP" --install-location /Applications \
         --identifier "$IDENTIFIER" --version "$VERSION" \
         "build/component.pkg" > /dev/null
productbuild --synthesize --package "build/component.pkg" "build/distribution.xml" > /dev/null
# give the installer window a proper title
sed -i '' "s|<installer-gui-script minSpecVersion=\"1\">|<installer-gui-script minSpecVersion=\"1\"><title>Touch Enabled Mac</title>|" "build/distribution.xml"
productbuild --distribution "build/distribution.xml" --package-path build "$PKG" > /dev/null
rm "build/component.pkg" "build/distribution.xml"

echo "✓ $DMG"
echo "✓ $PKG"
