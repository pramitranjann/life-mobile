#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PLIST="App/Resources/Info.plist"
WIDGET_PLIST="Widgets/Info.plist"

# 1. Refuse to build from drifted metadata, then bump app + widget together.
appVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
appBuild=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
widgetVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WIDGET_PLIST")
widgetBuild=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$WIDGET_PLIST")

[ "$appVersion" = "$widgetVersion" ] \
  || { echo "ERROR: app/widget marketing versions differ: ${appVersion} vs ${widgetVersion}" >&2; exit 1; }
[ "$appBuild" = "$widgetBuild" ] \
  || { echo "ERROR: app/widget build versions differ: ${appBuild} vs ${widgetBuild}" >&2; exit 1; }
git diff --quiet \
  || { echo "ERROR: commit tracked source changes before building a release IPA" >&2; exit 1; }
git diff --cached --quiet \
  || { echo "ERROR: clear or commit the staged index before building a release IPA" >&2; exit 1; }
source_commit=$(git rev-parse HEAD)

next=$(( appBuild + 1 ))
build_succeeded=false
restore_metadata_on_failure() {
  if [ "$build_succeeded" != true ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $appBuild" "$APP_PLIST" >/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $widgetBuild" "$WIDGET_PLIST" >/dev/null
    rm -f dist/.PRLifeMobile.ipa.tmp
    rm -f dist/.PRLifeMobile.ipa.provenance.tmp
    echo "Build failed; restored app/widget build metadata to ${appVersion} (${appBuild})." >&2
  fi
}
trap restore_metadata_on_failure EXIT

for plist in "$APP_PLIST" "$WIDGET_PLIST"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$plist"
done
shortVersion="$appVersion"
echo "Building version ${shortVersion} (build ${next})"

# 2. Generate project + build unsigned Release for a real device.
xcodegen generate
rm -rf build/ipa build/ipa-package
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

# 3. Package and verify a temporary IPA before replacing the last known-good one.
mkdir -p build/ipa-package/Payload dist
cp -R "$APP" "build/ipa-package/Payload/"
( cd build/ipa-package && zip -qry "../../dist/.PRLifeMobile.ipa.tmp" Payload )
verification=$(./scripts/verify-ipa.sh dist/.PRLifeMobile.ipa.tmp)
printf '%s\n' "$verification"
sha256=$(printf '%s\n' "$verification" | sed -n 's/^SHA256=//p')
printf 'SOURCE_COMMIT=%s\nSHA256=%s\nAPP_VERSION=%s\nAPP_BUILD=%s\n' \
  "$source_commit" "$sha256" "$shortVersion" "$next" \
  > dist/.PRLifeMobile.ipa.provenance.tmp
mv dist/.PRLifeMobile.ipa.tmp dist/PRLifeMobile.ipa
mv dist/.PRLifeMobile.ipa.provenance.tmp dist/PRLifeMobile.ipa.provenance
size=$(stat -f%z dist/PRLifeMobile.ipa)
build_succeeded=true

echo "✅ dist/PRLifeMobile.ipa  (${size} bytes)  version ${shortVersion} build ${next}"
echo "SHA-256: ${sha256}"
echo "Source commit: ${source_commit}"
echo "Next: publish this exact IPA as a GitHub prerelease candidate:"
echo "  ./scripts/publish-candidate.sh --notes \"What changed in this release.\""
echo "Install the printed direct URL on the physical device. After it passes, run:"
echo "  ./scripts/release.sh --physical-device-gate-sha256 ${sha256} --notes \"What changed in this release.\""
