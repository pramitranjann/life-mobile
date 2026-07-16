#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERIFY="./scripts/verify-ipa.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/prlife-ipa-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "TEST FAILURE: $*" >&2
  exit 1
}

make_plist() {
  local path="$1"
  local executable="$2"
  local version="$3"
  local build="$4"

  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $executable" "$path" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$path" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build" "$path" >/dev/null
}

make_widget_plist() {
  local path="$1"
  local version="$2"
  local build="$3"

  make_plist "$path" FixtureWidgets "$version" "$build"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.pramitranjan.prlife.widgets" "$path" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :NSExtension dict" "$path" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionPointIdentifier string com.apple.widgetkit-extension" "$path" >/dev/null
}

make_fixture() {
  local destination="$1"
  local widget_version="$2"
  local widget_build="$3"
  local architecture="${4:-arm64}"
  local root="$tmp/fixture"
  local app="$root/Payload/Fixture.app"
  local widget="$app/PlugIns/FixtureWidgets.appex"

  rm -rf "$root"
  mkdir -p "$widget"
  make_plist "$app/Info.plist" FixtureApp 1.2.3 42
  make_widget_plist "$widget/Info.plist" "$widget_version" "$widget_build"

  printf 'int main(void) { return 0; }\n' \
    | xcrun clang -arch "$architecture" -x c - -o "$app/FixtureApp"
  cp "$app/FixtureApp" "$widget/FixtureWidgets"
  (cd "$root" && zip -qry "$destination" Payload)
}

expect_failure() {
  local expected="$1"
  shift
  local output

  if output=$("$@" 2>&1); then
    fail "command unexpectedly passed: $*"
  fi
  printf '%s\n' "$output" | grep -Fq "$expected" \
    || fail "expected '$expected' in: $output"
}

valid="$tmp/valid.ipa"
make_fixture "$valid" 1.2.3 42
output=$(IPA_MIN_BYTES=1 "$VERIFY" "$valid")
printf '%s\n' "$output" | grep -Fq 'APP_VERSION=1.2.3' \
  || fail "valid fixture version was not reported"
printf '%s\n' "$output" | grep -Eq '^SHA256=[0-9a-f]{64}$' \
  || fail "valid fixture checksum was not reported"

expect_failure "unexpectedly small" "$VERIFY" "$valid"

mismatched_version="$tmp/mismatched-version.ipa"
make_fixture "$mismatched_version" 9.9.9 42
expect_failure "marketing version mismatch" env IPA_MIN_BYTES=1 "$VERIFY" "$mismatched_version"

mismatched_build="$tmp/mismatched-build.ipa"
make_fixture "$mismatched_build" 1.2.3 99
expect_failure "build version mismatch" env IPA_MIN_BYTES=1 "$VERIFY" "$mismatched_build"

wrong_architecture="$tmp/wrong-architecture.ipa"
make_fixture "$wrong_architecture" 1.2.3 42 x86_64
expect_failure "missing arm64 architecture" env IPA_MIN_BYTES=1 "$VERIFY" "$wrong_architecture"

wrong_widget="$tmp/wrong-widget.ipa"
make_fixture "$wrong_widget" 1.2.3 42
fixture_plist="$tmp/fixture/Payload/Fixture.app/PlugIns/FixtureWidgets.appex/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.example.not-a-widget" "$fixture_plist" >/dev/null
(cd "$tmp/fixture" && zip -qry "$wrong_widget" Payload)
expect_failure "expected exactly one WidgetKit extension" env IPA_MIN_BYTES=1 "$VERIFY" "$wrong_widget"

corrupt="$tmp/corrupt.ipa"
printf 'not a ZIP archive\n' > "$corrupt"
expect_failure "ZIP integrity check failed" env IPA_MIN_BYTES=1 "$VERIFY" "$corrupt"

echo "verify-ipa tests passed"
