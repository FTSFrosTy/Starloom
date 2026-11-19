#!/usr/bin/env bash
# Run after `flutter create` on the macOS build machine. Applies Starloom's
# iOS settings to the generated ios/ folder.
set -euo pipefail
cd "$(dirname "$0")/../.."

PLIST=ios/Runner/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" 2>/dev/null || true; }

# Keep playing with the screen locked / app in the background.
pb "Delete :UIBackgroundModes"
pb "Add :UIBackgroundModes array"
pb "Add :UIBackgroundModes:0 string audio"

# Show "On My iPhone > Starloom" in Files and in Apple Devices on Windows,
# so songs can be copied straight into the app.
pb "Delete :UIFileSharingEnabled"
pb "Add :UIFileSharingEnabled bool true"
pb "Delete :LSSupportsOpeningDocumentsInPlace"
pb "Add :LSSupportsOpeningDocumentsInPlace bool true"

# Sync with Starloom on your PC over home Wi-Fi.
pb "Delete :NSLocalNetworkUsageDescription"
pb "Add :NSLocalNetworkUsageDescription string Starloom connects to Starloom on your PC to sync playlists and songs."
pb "Delete :NSAppTransportSecurity"
pb "Add :NSAppTransportSecurity dict"
pb "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true"

pb "Delete :CFBundleDisplayName"
pb "Add :CFBundleDisplayName string Starloom"
pb "Delete :ITSAppUsesNonExemptEncryption"
pb "Add :ITSAppUsesNonExemptEncryption bool false"

# The audio engine needs iOS 15+.
sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' ios/Runner.xcodeproj/project.pbxproj
if [ -f ios/Podfile ]; then
  sed -i '' -E "s/^#? *platform :ios, '[0-9.]+'/platform :ios, '15.0'/" ios/Podfile
fi

# App icon: one 1024px image, Xcode makes the other sizes.
ICONSET=ios/Runner/Assets.xcassets/AppIcon.appiconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp tool/icon/icon-1024.png "$ICONSET/icon-1024.png"
cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images": [
    { "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON

echo "--- Info.plist after patch ---"
/usr/libexec/PlistBuddy -c "Print" "$PLIST" | head -80
grep -m3 IPHONEOS_DEPLOYMENT_TARGET ios/Runner.xcodeproj/project.pbxproj
