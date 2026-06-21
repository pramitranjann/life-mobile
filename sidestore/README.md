# Wireless updates via SideStore

## One-time setup
1. Push this repo to GitHub (the IPA is distributed via GitHub Releases; the source JSON via raw.githubusercontent).
2. In `sidestore/apps.json`, replace `USERNAME/REPO` with your GitHub repo, and set a real `iconURL` (drop a 1024px `icon.png` in `sidestore/`).
3. In the SideStore app on your iPhone: Sources → + → paste your raw `apps.json` URL.

## Each release (wireless update)
1. `./scripts/build-ipa.sh` — bumps the build number and produces `dist/PRLifeMobile.ipa`.
2. Create a GitHub Release (tag e.g. `v0.1.0-build<N>`) and upload `dist/PRLifeMobile.ipa` as an asset.
3. Edit `sidestore/apps.json`: prepend a new entry to the `versions` array (or bump the top one) with the new `version`/`buildVersion`, today's `date`, the new `downloadURL`, and the IPA `size` in bytes (printed by the script). Commit + push.
4. On your phone, SideStore shows an **Update** for PR Life — tap it. Done, over the air.

## Notes
- SideStore re-signs with YOUR Apple ID; the IPA here is intentionally **unsigned**.
- Free Apple ID: 7-day signing (SideStore auto-refreshes over Wi-Fi) + 3-app limit. The app is built to run on a free Apple ID (App-Group features degrade gracefully).
- API config (base URL + token) is pre-integrated via the bundled `LocalAPIConfig.plist` (gitignored), so no in-app setup is needed.
