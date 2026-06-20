#!/bin/bash
#
# PR Life — macOS installer.
# Double-click this file in Finder (or run it in Terminal) to build a signed
# Release copy of the macOS app and install it into /Applications as "PR Life.app".
#
# Why a script and not a prebuilt app: the app is sandboxed and uses an App Group +
# Keychain, which require signing with YOUR Apple ID. This script builds with your
# Xcode account (so signing succeeds) the same way Xcode does when you press Run.
#
set -euo pipefail

# Repo root = parent of this script's directory.
cd "$(dirname "$0")/.."
REPO="$(pwd)"
echo "PR Life installer — repo: $REPO"

# Regenerate the Xcode project (in case project.yml changed) and build signed Release.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

DERIVED="$REPO/build/mac"
echo "Building signed Release (this can take a minute)…"
xcodebuild \
  -scheme PRLifeMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build

SRC="$DERIVED/Build/Products/Release/PRLifeMac.app"
DEST="/Applications/PR Life.app"

if [ ! -d "$SRC" ]; then
  echo "ERROR: build did not produce $SRC" >&2
  exit 1
fi

echo "Installing to: $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Launching PR Life…"
open "$DEST"

echo ""
echo "Done. PR Life is now in /Applications (find it in Finder or Spotlight)."
echo "Open it, go to Settings, and turn on 'Launch at login' so it starts with your Mac."
