# Wireless updates via SideStore

## One-time setup
1. Push this repo to GitHub (the IPA is distributed via GitHub Releases; the source JSON via raw.githubusercontent).
2. In `sidestore/apps.json`, replace `USERNAME/REPO` with your GitHub repo, and set a real `iconURL` (drop a 1024px `icon.png` in `sidestore/`).
3. In the SideStore app on your iPhone: Sources → + → paste your raw `apps.json` URL.

## Each release (wireless update)
1. `./scripts/build-ipa.sh` — bumps the build number and produces `dist/PRLifeMobile.ipa`.
2. `./scripts/publish-candidate.sh --notes "What changed"` — pushes the source commit, tags it, uploads the verified IPA as a GitHub prerelease, and prints its direct install URL.
3. Install that exact URL on the physical iPhone and complete the release's device checklist.
4. After the device gate passes, run `./scripts/release.sh --physical-device-gate-sha256 <printed-sha> --notes "What changed"`.
5. The release script verifies the tested asset, updates `sidestore/apps.json`, promotes the GitHub prerelease, and then pushes the catalog. SideStore then shows the approved **Update**.

Candidates never enter the SideStore source before the physical-device gate. The direct candidate URL always has this stable form:

`https://github.com/pramitranjann/life-mobile/releases/download/v<version>-build<build>/PRLifeMobile.ipa`

Release tags identify the committed source used to build the IPA. The later catalog commit records the approved app/widget build metadata and SideStore entry.

## Notes
- SideStore re-signs with YOUR Apple ID; the IPA here is intentionally **unsigned**.
- Free Apple ID: 7-day signing (SideStore auto-refreshes over Wi-Fi) + 3-app limit. The app is built to run on a free Apple ID (App-Group features degrade gracefully).
- API config (base URL + token) is pre-integrated via the bundled `LocalAPIConfig.plist` (gitignored), so no in-app setup is needed.
