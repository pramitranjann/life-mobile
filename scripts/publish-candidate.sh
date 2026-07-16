#!/usr/bin/env bash
# Pushes the exact verified IPA as a GitHub prerelease candidate so it can be
# installed on a physical device before the SideStore catalog is updated.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="pramitranjann/life-mobile"
APP_PLIST="App/Resources/Info.plist"
WIDGET_PLIST="Widgets/Info.plist"
IPA="dist/PRLifeMobile.ipa"
PROVENANCE="dist/PRLifeMobile.ipa.provenance"
notes="${RELEASE_NOTES:-Physical-device release candidate.}"

if [ "${1:-}" = "--notes" ]; then
  [ "$#" -eq 2 ] || { echo "Usage: $0 [--notes TEXT]" >&2; exit 2; }
  notes="$2"
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--notes TEXT]" >&2
  exit 2
fi

[ "$(git branch --show-current)" = "main" ] \
  || { echo "ERROR: candidates must be published from main" >&2; exit 1; }
[ -f "$IPA" ] || { echo "ERROR: $IPA not found" >&2; exit 1; }
[ -f "$PROVENANCE" ] || { echo "ERROR: $PROVENANCE not found" >&2; exit 1; }
git diff --cached --quiet \
  || { echo "ERROR: candidate index contains staged changes" >&2; exit 1; }
unexpected_changes=$(git diff --name-only -- . \
  | awk -v app="$APP_PLIST" -v widget="$WIDGET_PLIST" '$0 != app && $0 != widget { print }')
[ -z "$unexpected_changes" ] \
  || { printf 'ERROR: tracked changes outside build metadata:\n%s\n' "$unexpected_changes" >&2; exit 1; }
untracked_inputs=$(git ls-files --others --exclude-standard -- App Widgets Sources)
[ -z "$untracked_inputs" ] \
  || { printf 'ERROR: untracked build inputs are not covered by source provenance:\n%s\n' "$untracked_inputs" >&2; exit 1; }

verification=$(./scripts/verify-ipa.sh "$IPA")
printf '%s\n' "$verification"
version=$(printf '%s\n' "$verification" | sed -n 's/^APP_VERSION=//p')
build=$(printf '%s\n' "$verification" | sed -n 's/^APP_BUILD=//p')
size=$(printf '%s\n' "$verification" | sed -n 's/^IPA_SIZE=//p')
sha256=$(printf '%s\n' "$verification" | sed -n 's/^SHA256=//p')

provenance_commit=$(sed -n 's/^SOURCE_COMMIT=//p' "$PROVENANCE")
provenance_sha256=$(sed -n 's/^SHA256=//p' "$PROVENANCE")
[ "$provenance_commit" = "$(git rev-parse HEAD)" ] \
  || { echo "ERROR: IPA was built from a different source commit" >&2; exit 1; }
[ "$provenance_sha256" = "$sha256" ] \
  || { echo "ERROR: IPA checksum does not match its provenance" >&2; exit 1; }

source_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
source_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
widget_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WIDGET_PLIST")
widget_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$WIDGET_PLIST")
[ "$source_version" = "$version" ] && [ "$source_build" = "$build" ] \
  || { echo "ERROR: app metadata does not match IPA" >&2; exit 1; }
[ "$widget_version" = "$version" ] && [ "$widget_build" = "$build" ] \
  || { echo "ERROR: widget metadata does not match IPA" >&2; exit 1; }
for plist in "$APP_PLIST" "$WIDGET_PLIST"; do
  python3 - "$plist" <<'PY'
import plistlib, subprocess, sys
path = sys.argv[1]
committed = plistlib.loads(subprocess.check_output(["git", "show", f"HEAD:{path}"]))
with open(path, "rb") as f:
    current = plistlib.load(f)
committed["CFBundleVersion"] = current.get("CFBundleVersion")
if committed != current:
    raise SystemExit(f"ERROR: {path} contains changes beyond CFBundleVersion")
PY
done

tag="v${version}-build${build}"
url="https://github.com/${REPO}/releases/download/${tag}/PRLifeMobile.ipa"

remote_tag_target() {
  git ls-remote origin "refs/tags/$1" "refs/tags/$1^{}" \
    | awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print (peeled != "" ? peeled : direct) }'
}

local_tag_exists=false
if git show-ref --verify --quiet "refs/tags/${tag}"; then
  [ "$(git rev-list -n 1 "$tag")" = "$provenance_commit" ] \
    || { echo "ERROR: existing local tag does not point to the IPA source commit" >&2; exit 1; }
  local_tag_exists=true
fi
remote_tag_commit=$(remote_tag_target "$tag")
if [ -n "$remote_tag_commit" ]; then
  [ "$remote_tag_commit" = "$provenance_commit" ] \
    || { echo "ERROR: existing remote tag does not point to the IPA source commit" >&2; exit 1; }
fi

git push origin main
if [ "$local_tag_exists" = false ]; then
  git tag -a "$tag" "$provenance_commit" -m "PR Life ${version} (build ${build}) release candidate"
fi
if [ -z "$remote_tag_commit" ]; then
  git push origin "$tag"
fi

if candidate_json=$(gh release view "$tag" --repo "$REPO" --json isPrerelease,assets 2>/dev/null); then
  [ "$(printf '%s' "$candidate_json" | jq -r '.isPrerelease')" = "true" ] \
    || { echo "ERROR: existing release is not a prerelease candidate: ${tag}" >&2; exit 1; }
  candidate_sha=$(printf '%s' "$candidate_json" \
    | jq -r '.assets[] | select(.name == "PRLifeMobile.ipa") | .digest' \
    | sed 's/^sha256://')
  candidate_size=$(printf '%s' "$candidate_json" \
    | jq -r '.assets[] | select(.name == "PRLifeMobile.ipa") | .size')
  if [ -z "$candidate_sha" ] && [ -z "$candidate_size" ]; then
    gh release upload "$tag" "$IPA" --repo "$REPO"
    candidate_json=$(gh release view "$tag" --repo "$REPO" --json isPrerelease,assets)
    candidate_sha=$(printf '%s' "$candidate_json" \
      | jq -r '.assets[] | select(.name == "PRLifeMobile.ipa") | .digest' \
      | sed 's/^sha256://')
    candidate_size=$(printf '%s' "$candidate_json" \
      | jq -r '.assets[] | select(.name == "PRLifeMobile.ipa") | .size')
  fi
  [ "$candidate_sha" = "$sha256" ] \
    || { echo "ERROR: existing candidate asset checksum differs from this IPA" >&2; exit 1; }
  [ "$candidate_size" = "$size" ] \
    || { echo "ERROR: existing candidate asset size differs from this IPA" >&2; exit 1; }
else
  gh release create "$tag" "$IPA" \
    --repo "$REPO" \
    --verify-tag \
    --prerelease \
    --title "PR Life ${version} (${build}) - release candidate" \
    --notes "${notes} Physical-device approval pending. SHA-256: ${sha256}"
fi

echo "CANDIDATE_URL=${url}"
echo "SHA256=${sha256}"
