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
done < <(find "$DERIVED" -maxdepth 6 -path "*PRLifeMobile-*/Build/Products/*/PRLifeMac.app" -type d 2>/dev/null)

if [ -z "$SRC" ]; then
  echo ""
  echo "Couldn't find a built app. In Xcode, press Cmd-R once (scheme: PRLifeMac,"
  echo "destination: My Mac) to build it, then run this installer again."
  exit 1
fi
echo "Found: $SRC"

# Refuse to install an unsigned build (won't run from /Applications and can't be a login item).
if ! codesign --verify --strict "$SRC" >/dev/null 2>&1; then
  echo ""
  echo "That build isn't properly signed (probably a command-line build)."
  echo "In Xcode, press Cmd-R once to produce a signed build, then run this installer again."
  exit 1
fi

echo "Installing to: $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

echo "Launching PR Life…"
open "$DEST"

echo ""
echo "Done — 'PR Life' is now in /Applications (Finder & Spotlight can find it)."
echo "In the app: Settings → turn on 'Launch at login' so it starts with your Mac."
