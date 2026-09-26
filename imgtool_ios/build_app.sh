#!/bin/bash
set -e

echo "=== Building IMG Tool iOS with PVR Texture Studio ==="

APP_DIR="Payload/IMGTool.app"
rm -rf Payload IMGTool_iOS.ipa
mkdir -p "$APP_DIR"

# 1. Compile Swift sources with arm64 iOS SDK
echo "1. Compiling Swift code..."
xcrun -sdk iphoneos swiftc \
    IMGToolApp/App/AppDelegate.swift \
    IMGToolApp/Core/IMGEntry.swift \
    IMGToolApp/Core/IMGArchive.swift \
    IMGToolApp/Core/DocumentPicker.swift \
    IMGToolApp/Core/ImagePicker.swift \
    IMGToolApp/Core/PVRTextureEntry.swift \
    IMGToolApp/Core/PVRTCDecompressor.swift \
    IMGToolApp/Core/PVRTCCompressor.swift \
    IMGToolApp/Core/PVRDatabase.swift \
    IMGToolApp/Views/ArchiveHeaderView.swift \
    IMGToolApp/Views/EntryRowView.swift \
    IMGToolApp/Views/DFFViewerSheet.swift \
    IMGToolApp/Views/RebuildSheet.swift \
    IMGToolApp/Views/ModdingGuideSheet.swift \
    IMGToolApp/Views/TextureRowView.swift \
    IMGToolApp/Views/TextureDetailSheet.swift \
    IMGToolApp/Views/AddTextureSheet.swift \
    IMGToolApp/Views/PVRDatabasePickerSheet.swift \
    IMGToolApp/Views/TextureListView.swift \
    IMGToolApp/Views/ContentView.swift \
    -module-name IMGTool \
    -target arm64-apple-ios14.0 \
    -O \
    -framework UIKit \
    -framework SwiftUI \
    -framework WebKit \
    -framework UniformTypeIdentifiers \
    -framework Combine \
    -framework CoreGraphics \
    -framework PhotosUI \
    -o "$APP_DIR/IMGTool"

echo "Binary compiled successfully!"

# 2. Copy Info.plist
echo "2. Copying Info.plist..."
cp IMGToolApp/App/Info.plist "$APP_DIR/Info.plist"

# 3. Compile AppIcon with actool
echo "3. Compiling AppIcon with actool..."
xcrun actool IMGToolApp/Assets.xcassets \
    --compile "$APP_DIR" \
    --platform iphoneos \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-format human-readable-text || true

# Also copy raw PNG icons and iTunesArtwork directly to app root as fallback
cp IMGToolApp/Assets.xcassets/AppIcon.appiconset/*.png "$APP_DIR/" || true
cp IMGToolApp/Assets.xcassets/AppIcon.appiconset/iTunesArtwork* "$APP_DIR/" || true

# 4. Copy 3D DFF Preview resources to dff_preview/ and bundle root
echo "4. Bundling 3D DFF Preview assets..."
mkdir -p "$APP_DIR/dff_preview"
cp -r IMGToolApp/Resources/dff_preview/* "$APP_DIR/dff_preview/"
cp -r IMGToolApp/Resources/dff_preview/* "$APP_DIR/"

# 5. Ad-hoc codesign
echo "5. Applying ad-hoc codesign..."
codesign -s - --force "$APP_DIR"

# 6. Package IPA with iTunesArtwork
echo "6. Packaging IMGTool_iOS.ipa..."
cp IMGToolApp/Assets.xcassets/AppIcon.appiconset/iTunesArtwork* . || true
zip -r9 IMGTool_iOS.ipa Payload iTunesArtwork iTunesArtwork@2x 2>/dev/null || zip -r9 IMGTool_iOS.ipa Payload

echo "=== SUCCESS! IMGTool_iOS.ipa is ready! ==="
ls -lh IMGTool_iOS.ipa
