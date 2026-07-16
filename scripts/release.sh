#!/usr/bin/env bash
# Publishes the exact IPA that already passed the physical-device gate, updates
# the SideStore source, and pushes. Building is deliberately a separate step.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="pramitranjann/life-mobile"
APP_PLIST="App/Resources/Info.plist"
WIDGET_PLIST="Widgets/Info.plist"
IPA="dist/PRLifeMobile.ipa"
PROVENANCE="dist/PRLifeMobile.ipa.provenance"

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh --physical-device-gate-sha256 SHA256 [--notes TEXT | --notes-file PATH]

Release notes may also be supplied through RELEASE_NOTES. If omitted, a
human-readable generic description is used.

This command publishes the existing dist/PRLifeMobile.ipa; it never rebuilds
or bumps a version. Run scripts/build-ipa.sh first, install and test that exact
IPA on the physical device, then pass its SHA-256 with
--physical-device-gate-sha256. The IPA is fully verified again before any
manifest update, commit, GitHub release, or push.
EOF
}

release_notes="${RELEASE_NOTES:-}"
physical_device_gate_sha256=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --physical-device-gate-sha256)
      [ "$#" -ge 2 ] || { echo "ERROR: --physical-device-gate-sha256 requires a checksum" >&2; exit 2; }
      physical_device_gate_sha256="$2"
      shift 2
      ;;
    --notes)
      [ "$#" -ge 2 ] || { echo "ERROR: --notes requires text" >&2; exit 2; }
      release_notes="$2"
      shift 2
      ;;
    --notes-file)
      [ "$#" -ge 2 ] || { echo "ERROR: --notes-file requires a path" >&2; exit 2; }
      [ -f "$2" ] || { echo "ERROR: release notes file not found: $2" >&2; exit 2; }
      release_notes=$(<"$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$physical_device_gate_sha256" ] || {
  echo "ERROR: refusing to publish without --physical-device-gate-sha256" >&2
  echo "Install and test the existing dist/PRLifeMobile.ipa, then pass its printed SHA-256." >&2
  exit 2
}
printf '%s' "$physical_device_gate_sha256" | grep -Eq '^[0-9a-fA-F]{64}$' \
  || { echo "ERROR: physical-device gate checksum must contain 64 hex characters" >&2; exit 2; }
physical_device_gate_sha256=$(printf '%s' "$physical_device_gate_sha256" | tr '[:upper:]' '[:lower:]')

if ! printf '%s' "$release_notes" | grep -q '[^[:space:]]'; then
  release_notes="Updates the PR Life native companion with the latest fixes and improvements."
fi

[ "$(git branch --show-current)" = "main" ] \
  || { echo "ERROR: releases must be run from the local main branch" >&2; exit 1; }
[ -f "$IPA" ] || { echo "ERROR: $IPA not found"; exit 1; }
[ -f "$PROVENANCE" ] || { echo "ERROR: $PROVENANCE not found; rebuild the IPA" >&2; exit 1; }

# 1. Verify the exact, already device-tested artifact before the first manifest
# update, commit, release, or push. Use
# metadata from the IPA itself so the tag and source catalog cannot drift from it.
verification=$(./scripts/verify-ipa.sh "$IPA")
printf '%s\n' "$verification"
version=$(printf '%s\n' "$verification" | sed -n 's/^APP_VERSION=//p')
build=$(printf '%s\n' "$verification" | sed -n 's/^APP_BUILD=//p')
size=$(printf '%s\n' "$verification" | sed -n 's/^IPA_SIZE=//p')
sha256=$(printf '%s\n' "$verification" | sed -n 's/^SHA256=//p')
[ -n "$version" ] && [ -n "$build" ] && [ -n "$size" ] && [ -n "$sha256" ] \
  || { echo "ERROR: verifier did not return complete artifact metadata" >&2; exit 1; }
[ "$sha256" = "$physical_device_gate_sha256" ] \
  || { echo "ERROR: current IPA checksum does not match the physically tested artifact" >&2; exit 1; }

provenance_commit=$(sed -n 's/^SOURCE_COMMIT=//p' "$PROVENANCE")
provenance_sha256=$(sed -n 's/^SHA256=//p' "$PROVENANCE")
printf '%s' "$provenance_commit" | grep -Eq '^[0-9a-f]{40}$' \
  || { echo "ERROR: invalid source commit in $PROVENANCE" >&2; exit 1; }
[ "$provenance_sha256" = "$sha256" ] \
  || { echo "ERROR: IPA checksum does not match its build provenance" >&2; exit 1; }
[ "$provenance_commit" = "$(git rev-parse HEAD)" ] \
  || { echo "ERROR: IPA was built from a different source commit" >&2; exit 1; }
git diff --cached --quiet \
  || { echo "ERROR: release index contains staged changes" >&2; exit 1; }
unexpected_changes=$(git diff --name-only -- . \
  | awk -v app="$APP_PLIST" -v widget="$WIDGET_PLIST" '$0 != app && $0 != widget { print }')
[ -z "$unexpected_changes" ] \
  || { echo "ERROR: tracked changes outside release metadata:\n$unexpected_changes" >&2; exit 1; }
git diff --quiet -- "$APP_PLIST" \
  && { echo "ERROR: app build metadata was not bumped by build-ipa.sh" >&2; exit 1; }
git diff --quiet -- "$WIDGET_PLIST" \
  && { echo "ERROR: widget build metadata was not bumped by build-ipa.sh" >&2; exit 1; }

source_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
source_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
[ "$source_version" = "$version" ] && [ "$source_build" = "$build" ] \
  || { echo "ERROR: source app version ${source_version} (${source_build}) does not match IPA ${version} (${build})" >&2; exit 1; }

source_widget_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WIDGET_PLIST")
source_widget_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$WIDGET_PLIST")
[ "$source_widget_version" = "$version" ] && [ "$source_widget_build" = "$build" ] \
  || { echo "ERROR: source widget version ${source_widget_version} (${source_widget_build}) does not match IPA ${version} (${build})" >&2; exit 1; }

tag="v${version}-build${build}"
url="https://github.com/${REPO}/releases/download/${tag}/PRLifeMobile.ipa"
git show-ref --verify --quiet "refs/tags/${tag}" \
  && { echo "ERROR: local tag already exists: ${tag}" >&2; exit 1; }

echo "Releasing ${tag} (size ${size}, SHA-256 ${sha256})"

# 2. Prepare and validate the SideStore source manifest before publishing.
python3 - "$version" "$build" "$url" "$size" "$sha256" "$release_notes" <<'PY'
import json, sys, datetime
version, build, url = sys.argv[1:4]
size, sha256, release_notes = int(sys.argv[4]), sys.argv[5], sys.argv[6]
path = "sidestore/apps.json"
with open(path) as f: src = json.load(f)
entry = {
    "version": version,
    "buildVersion": build,
    "date": datetime.date.today().isoformat(),
    "localizedDescription": release_notes,
    "downloadURL": url,
    "size": size,
    "sha256": sha256,
    "minOSVersion": "17.0",
}
app = src["apps"][0]
app.setdefault("versions", [])
app["versions"] = [entry] + [v for v in app["versions"] if v.get("buildVersion") != build]
# top-level convenience fields some SideStore builds read
app["version"] = version
app["versionDate"] = entry["date"]
app["downloadURL"] = url
app["size"] = size
app["sha256"] = sha256
with open(path, "w") as f:
    json.dump(src, f, indent=2)
    f.write("\n")
with open(path) as f: json.load(f)
print("apps.json prepared ->", version, build, sha256)
PY

# 3. Commit only the release metadata paths, preserving any unrelated staged work.
git add "$APP_PLIST" "$WIDGET_PLIST" sidestore/apps.json
git commit --only -m "release: ${tag}" -- "$APP_PLIST" "$WIDGET_PLIST" sidestore/apps.json

# 4. Push an explicit tag at the local release commit. `--verify-tag` prevents
# GitHub CLI from silently creating the release tag at an older remote-main commit.
git tag -a "$tag" -m "PR Life ${version} (build ${build})"
git push origin "$tag"
gh release create "$tag" "$IPA" \
  --repo "$REPO" \
  --verify-tag \
  --title "PR Life ${version} (build ${build})" \
  --notes "$release_notes"

# 5. Expose the SideStore manifest only after its release asset exists.
git push origin main

echo "✅ Released ${tag}"
echo "SideStore source URL: https://raw.githubusercontent.com/${REPO}/main/sidestore/apps.json"
