#!/usr/bin/env bash
# One command to publish a new version: builds the IPA, cuts a GitHub Release,
# updates the SideStore source, and pushes. Your phone then shows "Update".
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="pramitranjann/life-mobile"
APP_PLIST="App/Resources/Info.plist"
IPA="dist/PRLifeMobile.ipa"

# 1. Build the IPA (bumps the build number, produces dist/PRLifeMobile.ipa).
./scripts/build-ipa.sh

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
[ -f "$IPA" ] || { echo "ERROR: $IPA not found"; exit 1; }
size=$(stat -f%z "$IPA")
tag="v${version}-build${build}"
url="https://github.com/${REPO}/releases/download/${tag}/PRLifeMobile.ipa"

echo "Releasing ${tag} (size ${size})"

# 2. Commit the build-number bump.
git add "$APP_PLIST" Widgets/Info.plist
git commit -m "chore: build ${version} (${build})" || true

# 3. Create the GitHub Release with the IPA attached.
gh release create "$tag" "$IPA" \
  --repo "$REPO" \
  --title "PR Life ${version} (build ${build})" \
  --notes "Sideload build ${version} (${build})."

# 4. Update the SideStore source manifest with this version.
python3 - "$version" "$build" "$url" "$size" <<'PY'
import json, sys, datetime
version, build, url, size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
path = "sidestore/apps.json"
with open(path) as f: src = json.load(f)
entry = {
    "version": version,
    "buildVersion": build,
    "date": datetime.date.today().isoformat(),
    "localizedDescription": f"Build {version} ({build}).",
    "downloadURL": url,
    "size": size,
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
with open(path, "w") as f:
    json.dump(src, f, indent=2)
    f.write("\n")
print("apps.json updated ->", version, build)
PY

# 5. Push the updated source so SideStore detects the update.
git add sidestore/apps.json
git commit -m "release: ${tag}"
git push origin main

echo "✅ Released ${tag}"
echo "SideStore source URL: https://raw.githubusercontent.com/${REPO}/main/sidestore/apps.json"
