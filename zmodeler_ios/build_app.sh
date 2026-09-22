#!/bin/bash
set -e

echo "=== Building Diro 3D Studio (ZModeler iOS) ==="

APP_DIR="Payload/ZModeler.app"
rm -rf Payload ZModeler_iOS.ipa
mkdir -p "$APP_DIR"

# 1. Compile Swift sources with arm64 iOS SDK
echo "1. Compiling Swift code..."
xcrun -sdk iphoneos swiftc \
    ZModelerApp/AppDelegate.swift \
    ZModelerApp/ViewController.swift \
    -module-name ZModeler \
    -target arm64-apple-ios14.0 \
    -O \
    -framework UIKit \
    -framework WebKit \
    -framework UniformTypeIdentifiers \
    -o "$APP_DIR/ZModeler"

echo "Binary compiled successfully!"

# 2. Copy Info.plist
echo "2. Copying Info.plist..."
cp ZModelerApp/Info.plist "$APP_DIR/Info.plist"

# 3. Compile AppIcon with actool
echo "3. Compiling AppIcon (diro.png) with actool..."
xcrun actool ZModelerApp/Assets.xcassets \
    --compile "$APP_DIR" \
    --platform iphoneos \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-format human-readable-text || true

# Also copy raw PNG icons and iTunesArtwork directly to app root as fallback
cp ZModelerApp/Assets.xcassets/AppIcon.appiconset/*.png "$APP_DIR/" || true
cp ZModelerApp/Assets.xcassets/AppIcon.appiconset/iTunesArtwork* "$APP_DIR/" || true

# 4. Copy Web/3D Studio assets to both bundle root and www/
echo "4. Bundling 3D Studio assets..."
cp -r ZModelerUI/* "$APP_DIR/"
mkdir -p "$APP_DIR/www"
cp -r ZModelerUI/* "$APP_DIR/www/"

# 5. Ad-hoc codesign
echo "5. Applying ad-hoc codesign..."
codesign -s - --force "$APP_DIR"

# 6. Package IPA with iTunesArtwork
echo "6. Packaging ZModeler_iOS.ipa..."
cp ZModelerApp/Assets.xcassets/AppIcon.appiconset/iTunesArtwork* . || true
zip -r9 ZModeler_iOS.ipa Payload iTunesArtwork iTunesArtwork@2x 2>/dev/null || zip -r9 ZModeler_iOS.ipa Payload

echo "=== SUCCESS! ZModeler_iOS.ipa is ready! ==="
ls -lh ZModeler_iOS.ipa
