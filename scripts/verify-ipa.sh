#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

IPA="${1:-dist/PRLifeMobile.ipa}"
MIN_BYTES="${IPA_MIN_BYTES:-524288}"
MAX_BYTES="${IPA_MAX_BYTES:-524288000}"
EXPECTED_WIDGET_BUNDLE_ID="${EXPECTED_WIDGET_BUNDLE_ID:-com.pramitranjan.prlife.widgets}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

file_size() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null \
    || fail "missing $2 in $1"
}

verify_bundle_architecture() {
  local bundle="$1"
  local label="$2"
  local executable archs

  executable=$(read_plist "$bundle/Info.plist" CFBundleExecutable)
  [ -f "$bundle/$executable" ] \
    || fail "$label executable not found: $bundle/$executable"

  archs=$(lipo -archs "$bundle/$executable" 2>/dev/null) \
    || fail "$label executable is not a valid Mach-O binary"
  case " $archs " in
    *" arm64 "*) ;;
    *) fail "$label executable is missing arm64 architecture (found: $archs)" ;;
  esac

  printf '%s' "$archs"
}

case "$MIN_BYTES:$MAX_BYTES" in
  *[!0-9:]*) fail "IPA_MIN_BYTES and IPA_MAX_BYTES must be positive integers" ;;
esac
[ "$MIN_BYTES" -gt 0 ] || fail "IPA_MIN_BYTES must be greater than zero"
[ "$MAX_BYTES" -ge "$MIN_BYTES" ] \
  || fail "IPA_MAX_BYTES must be greater than or equal to IPA_MIN_BYTES"

[ -f "$IPA" ] || fail "IPA not found: $IPA"

size=$(file_size "$IPA")
[ "$size" -ge "$MIN_BYTES" ] \
  || fail "IPA is unexpectedly small: ${size} bytes (minimum: ${MIN_BYTES})"
[ "$size" -le "$MAX_BYTES" ] \
  || fail "IPA is unexpectedly large: ${size} bytes (maximum: ${MAX_BYTES})"

unzip -tq "$IPA" >/dev/null 2>&1 || fail "IPA ZIP integrity check failed"

unsafe_entry=$(unzip -Z1 "$IPA" | awk '
  /^\// || /(^|\/)\.\.($|\/)/ { print; exit }
')
[ -z "$unsafe_entry" ] || fail "IPA contains an unsafe ZIP path: $unsafe_entry"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/prlife-ipa-verify.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
unzip -q "$IPA" -d "$tmp"

[ -d "$tmp/Payload" ] || fail "IPA is missing its Payload directory"
app_count=$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')
[ "$app_count" -eq 1 ] \
  || fail "IPA must contain exactly one top-level app bundle (found: $app_count)"
app=$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit)

app_version=$(read_plist "$app/Info.plist" CFBundleShortVersionString)
app_build=$(read_plist "$app/Info.plist" CFBundleVersion)
app_archs=$(verify_bundle_architecture "$app" "app")

plugins="$app/PlugIns"
[ -d "$plugins" ] || fail "app does not contain an embedded widget extension"
widget_count=$(find "$plugins" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | wc -l | tr -d ' ')
[ "$widget_count" -gt 0 ] || fail "app does not contain an embedded app extension"

widget_summaries=""
matched_widget_count=0
while IFS= read -r widget; do
  widget_name=$(basename "$widget")
  widget_version=$(read_plist "$widget/Info.plist" CFBundleShortVersionString)
  widget_build=$(read_plist "$widget/Info.plist" CFBundleVersion)
  [ "$widget_version" = "$app_version" ] \
    || fail "$widget_name marketing version mismatch: app=$app_version widget=$widget_version"
  [ "$widget_build" = "$app_build" ] \
    || fail "$widget_name build version mismatch: app=$app_build widget=$widget_build"
  widget_archs=$(verify_bundle_architecture "$widget" "$widget_name")
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$widget/Info.plist" 2>/dev/null || true)
  extension_point=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$widget/Info.plist" 2>/dev/null || true)
  if [ "$bundle_id" = "$EXPECTED_WIDGET_BUNDLE_ID" ] \
     && [ "$extension_point" = "com.apple.widgetkit-extension" ]; then
    matched_widget_count=$((matched_widget_count + 1))
    widget_summaries="${widget_summaries}${widget_name}:${widget_archs};"
  fi
done < <(find "$plugins" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | sort)
[ "$matched_widget_count" -eq 1 ] \
  || fail "expected exactly one WidgetKit extension with bundle id ${EXPECTED_WIDGET_BUNDLE_ID} (found: ${matched_widget_count})"

sha256=$(shasum -a 256 "$IPA" | awk '{print $1}')
printf '%s' "$sha256" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "could not calculate a valid SHA-256 checksum"

echo "IPA_PATH=$IPA"
echo "IPA_SIZE=$size"
echo "SHA256=$sha256"
echo "APP_VERSION=$app_version"
echo "APP_BUILD=$app_build"
echo "APP_ARCHS=$app_archs"
echo "APPEX_COUNT=$widget_count"
echo "WIDGET_COUNT=$matched_widget_count"
echo "WIDGETS=${widget_summaries%;}"
echo "IPA verification passed"
