#!/usr/bin/env bash
# Builds the Apple Watch app (unsigned) and puts it inside the iPhone app,
# where iOS expects a companion watch app: Runner.app/Watch/<name>.app.
# Sideloadly signs and installs both; the watch app then shows up in the
# iPhone's Watch app under "Available Apps".
set -euo pipefail
cd "$(dirname "$0")/../../watch"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet

xcodebuild -quiet \
  -project StarloomWatch.xcodeproj \
  -scheme StarloomWatch \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath ../build/watch \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="../build/watch/Build/Products/Release-watchos/StarloomWatch.app"
test -d "$APP"
RUNNER="../build/ios/iphoneos/Runner.app"
rm -rf "$RUNNER/Watch"
mkdir -p "$RUNNER/Watch"
cp -R "$APP" "$RUNNER/Watch/"
echo "Embedded watch app:"
ls -la "$RUNNER/Watch"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$RUNNER/Info.plist"
/usr/libexec/PlistBuddy -c "Print :WKCompanionAppBundleIdentifier" "$RUNNER/Watch/StarloomWatch.app/Info.plist"
