#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PLIST="App/Resources/Info.plist"
WIDGET_PLIST="Widgets/Info.plist"

# 1. Bump CFBundleVersion (build number) on the app + widget so they stay in lockstep.
current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
next=$(( current + 1 ))
for plist in "$APP_PLIST" "$WIDGET_PLIST"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$plist"
done
shortVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
echo "Building version ${shortVersion} (build ${next})"

# 2. Generate project + build unsigned Release for a real device.
xcodegen generate
rm -rf build/ipa dist
xcodebuild \
  -scheme PRLifeMobile \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build/ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ENABLE_BITCODE=NO \
  build | tail -8

APP="build/ipa/Build/Products/Release-iphoneos/PRLifeMobile.app"
if [ ! -d "$APP" ]; then echo "ERROR: built .app not found at $APP"; exit 1; fi

# 3. Package into an unsigned .ipa (Payload/ layout).
mkdir -p dist/Payload
cp -R "$APP" "dist/Payload/"
( cd dist && zip -qry "PRLifeMobile.ipa" Payload && rm -rf Payload )
size=$(stat -f%z dist/PRLifeMobile.ipa)
echo "✅ dist/PRLifeMobile.ipa  (${size} bytes)  version ${shortVersion} build ${next}"
echo "Next: upload dist/PRLifeMobile.ipa to your GitHub Release, update sidestore/apps.json (version/build/downloadURL/size), commit + push that JSON."
