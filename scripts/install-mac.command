#!/bin/bash
#
# PR Life — macOS installer (copy-only).
#
# Command-line signing doesn't work with a personal Apple team, so this script does
# NOT build. Instead:
#   1. In Xcode, open PRLifeMobile.xcodeproj, pick the "PRLifeMac" scheme + "My Mac",
#      and press Cmd-R (Run) once. That produces a properly SIGNED app and launches it.
#   2. Quit the app, then double-click this file. It copies the signed app Xcode just
#      built into /Applications as "PR Life.app" and opens it.
#
set -euo pipefail

DEST="/Applications/PR Life.app"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

echo "Looking for the app Xcode built…"
# Newest PRLifeMac.app under any PRLifeMobile-* DerivedData (Debug from Cmd-R, or Release).
SRC=""
NEWEST=0
while IFS= read -r app; do
  [ -d "$app" ] || continue
  m=$(stat -f %m "$app")
  if [ "$m" -gt "$NEWEST" ]; then NEWEST=$m; SRC="$app"; fi
done < <(find "$DERIVED" -maxdepth 6 -path "*PRLifeMobile-*/Build/Products/*/PRLifeMac.app" -not -path "*Index.noindex*" -type d 2>/dev/null)

if [ -z "$SRC" ]; then
  echo ""
  echo "Couldn't find a built app. In Xcode, press Cmd-R once (scheme: PRLifeMac,"
  echo "destination: My Mac) to build it, then run this installer again."
  exit 1
fi
echo "Found: $SRC"

# Refuse unsigned or tampered builds. Personal-team development certificates are not
# Gatekeeper trust anchors, so `codesign --verify` may return CSSMERR_TP_NOT_TRUSTED
# even when the code seal is intact (including for an app Xcode launched successfully).
verify_output=$(codesign --verify --strict "$SRC" 2>&1) || {
  if [[ "$verify_output" != *"CSSMERR_TP_NOT_TRUSTED"* ]]; then
    echo ""
    echo "That build isn't properly signed (probably a command-line build)."
    echo "In Xcode, press Cmd-R once to produce a signed build, then run this installer again."
    echo "$verify_output"
    exit 1
  fi
}

check_entitlements() {
  local target="$1"
  local label="$2"
  local output

  output=$(codesign -d --entitlements - "$target" 2>&1 || true)

  if [[ "$output" == *"invalid entitlements blob"* ]]; then
    echo ""
    echo "$label has an invalid entitlements blob, so macOS will ignore its App Group access."
    echo "Build the app from Xcode with Cmd-R (scheme: PRLifeMac, destination: My Mac),"
    echo "then run this installer again."
    exit 1
  fi

  if [[ "$output" != *"group.com.pramitranjan.prlife"* ]]; then
    echo ""
    echo "$label is missing the PR Life App Group entitlement."
    echo "Build the app from Xcode with Cmd-R (scheme: PRLifeMac, destination: My Mac),"
    echo "then run this installer again."
    exit 1
  fi
}

check_entitlements "$SRC" "The macOS app"
check_entitlements "$SRC/Contents/PlugIns/PRLifeMacWidgets.appex" "The macOS widget"

echo "Installing to: $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

echo "Launching PR Life…"
open "$DEST"

echo ""
echo "Done — 'PR Life' is now in /Applications (Finder & Spotlight can find it)."
echo "In the app: Settings → turn on 'Launch at login' so it starts with your Mac."
